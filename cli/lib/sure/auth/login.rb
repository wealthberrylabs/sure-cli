# frozen_string_literal: true

begin
  # Supplies IO#getpass and IO#noecho. Guarded because platforms without a
  # console extension must still load: prompt_secret refuses to read rather
  # than falling back to an echoed read.
  require "io/console"
rescue LoadError
  nil
end

require_relative "../config"
require_relative "../errors"
require_relative "../http/client"
require_relative "../http/url_builder"
require_relative "../output/result"
require_relative "../redactor"
require_relative "credential"
require_relative "credential_key"
require_relative "store_factory"

module Sure
  module Auth
    # Reads one API key from exactly one source, proves it with GET
    # /api/v1/usage, and only then persists it. The key never appears in argv,
    # in a child environment, or in rendered output.
    class Login
      MIN_BYTES = 4
      MAX_BYTES = 4096
      PROMPT = "API key: "
      ENV_KEY = "SURE_API_KEY"
      FLAG_GUIDANCE =
        "no API key was provided; use --api-key-file, --api-key-stdin, " \
        "or set #{ENV_KEY}"
      HIDDEN_INPUT_GUIDANCE =
        "cannot read a hidden API key on this terminal; use --api-key-file, " \
        "--api-key-stdin, or SURE_API_KEY"

      # Minimal provider for the validation request: the candidate key is
      # already in memory and must not be re-read from the store or env.
      class CandidateProvider
        def initialize(secret)
          @secret = secret
        end

        def fetch(_profile)
          [ @secret, :environment ]
        end

        def inspect
          "#<Sure::Auth::Login::CandidateProvider api_key=[REDACTED]>"
        end
      end

      def initialize(runtime:, options: {}, loader: nil, store_factory: nil)
        @runtime = runtime
        @options = options || {}
        @paths = Config::Paths.new(env: runtime.env)
        @loader = loader || Config::Loader.new(paths: @paths)
        @store_factory = store_factory
      end

      attr_reader :runtime, :options, :loader

      def call
        name = profile_name
        attributes = stored_attributes(name)
        server_url = resolve_server(attributes)
        secret = read_secret

        profile = build_profile(name, server_url, attributes)
        usage = validate!(profile, secret)

        scopes = Array(usage.dig("api_key", "scopes")).map(&:to_s)
        store = store_for(profile)
        key = CredentialKey.new(profile: name, origin: server_url)
        credential = Credential.new(
          kind: :api_key,
          secret: secret,
          server_url: server_url,
          created_at: now
        )

        mode = store.write(key, credential)
        warning = fallback_warning(store, attributes)
        persist!(name, server_url, scopes, mode, warning.nil?)

        result(name, server_url, scopes, mode, warning)
      rescue StandardError
        rollback(store, key) if defined?(store) && defined?(key) && store && key
        raise
      end

      private

      def result(name, server_url, scopes, mode, warning)
        warnings = warning.nil? ? [] : [ warning ]
        Output::Result.new(
          data: {
            "profile" => name,
            "server_url" => server_url,
            "authentication_method" => "api_key",
            "credential_source" => mode.to_s,
            "scopes" => scopes
          },
          meta: { warnings: warnings }
        )
      end

      def profile_name
        from_flag = option(:profile)
        return from_flag.to_s if present?(from_flag)

        from_env = runtime.env["SURE_PROFILE"]
        return from_env.to_s if present?(from_env)

        from_config = loader.load["default_profile"]
        return from_config.to_s if present?(from_config)

        "default"
      end

      def stored_attributes(name)
        profiles = loader.load.fetch("profiles", {})
        profiles.fetch(name, {})
      end

      def resolve_server(attributes)
        from_flag = option(:server)
        return from_flag.to_s if present?(from_flag)

        from_env = runtime.env["SURE_SERVER"]
        return from_env.to_s if present?(from_env)

        from_profile = attributes["server_url"]
        return from_profile.to_s if present?(from_profile)

        raise Errors::UsageError,
              "no server URL for the selected profile; pass --server or set SURE_SERVER"
      end

      def build_profile(name, server_url, _attributes)
        # One precedence implementation for server, CA bundle, TLS, timeouts,
        # scopes, credential store, and warning flags. Login must reach the same
        # private-CA server every other command can reach.
        Config::Resolver.new(
          env: runtime.env,
          options: options.merge(server: server_url),
          loader: loader,
          cwd: runtime.cwd,
          stderr: runtime.stderr
        ).resolve(profile_name: name)
      end

      def validate!(profile, secret)
        client = HTTP::Client.new(
          profile: profile,
          auth_provider: CandidateProvider.new(secret),
          url_builder: HTTP::UrlBuilder.new(profile.server_url, stderr: runtime.stderr),
          runtime: runtime,
          redactor: Redactor.new(active_secret: secret)
        )

        body = client.get("/api/v1/usage").body
        unless body.is_a?(Hash)
          raise Errors::GeneralError, "GET /api/v1/usage returned an unexpected response"
        end

        body
      end

      def read_secret
        file = option(:api_key_file)
        stdin = truthy?(option(:api_key_stdin))

        if present?(file) && stdin
          raise Errors::UsageError, "--api-key-file and --api-key-stdin are mutually exclusive"
        end

        if present?(file)
          raise Errors::UsageError, "--api-key-file - is not supported; use --api-key-stdin" if file.to_s == "-"

          read_file(file.to_s)
        elsif stdin
          normalize_secret(runtime.stdin.read)
        else
          environment_secret || prompt_secret
        end
      end

      def environment_secret
        raw = runtime.env[ENV_KEY]
        return nil if raw.nil?

        normalize_secret(raw)
      end

      def prompt_secret
        unless tty?(runtime.stdin)
          raise Errors::UsageError, FLAG_GUIDANCE
        end

        runtime.stderr.print(PROMPT)
        runtime.stderr.flush if runtime.stderr.respond_to?(:flush)

        raw = if runtime.stdin.respond_to?(:getpass)
          runtime.stdin.getpass
        elsif runtime.stdin.respond_to?(:noecho)
          runtime.stdin.noecho { runtime.stdin.gets }
        else
          # Never fall back to an echoed read for a secret.
          raise Errors::UsageError, HIDDEN_INPUT_GUIDANCE
        end

        normalize_secret(raw)
      end

      def read_file(path)
        unless File.file?(path)
          raise Errors::UsageError, "API key file #{path} does not exist"
        end

        warn_readable_file(path)
        normalize_secret(File.read(path))
      end

      def warn_readable_file(path)
        return if Gem.win_platform?
        return if (File.stat(path).mode & 0o077).zero?

        runtime.stderr.puts(
          "warning: #{path} is group/world readable; run `chmod 600 #{path}`"
        )
      end

      def normalize_secret(raw)
        value = raw.to_s
        if value.bytesize > MAX_BYTES
          raise Errors::UsageError, "API key must be at most #{MAX_BYTES} bytes"
        end

        value = value.sub(/\r?\n\z/, "")
        if value.strip.empty?
          raise Errors::UsageError, "API key must not be empty or whitespace"
        end
        if value.match?(/[\r\n\0]/)
          raise Errors::UsageError, "API key must not contain CR, LF, or NUL characters"
        end
        if value.bytesize < MIN_BYTES
          raise Errors::UsageError,
                "API key must be at least #{MIN_BYTES} bytes"
        end

        value
      end

      def store_for(profile)
        @store_factory ||= StoreFactory.new(profile: profile, env: runtime.env)
      end

      def fallback_warning(store, attributes)
        return nil unless store.mode == :file
        return nil if attributes["plaintext_warning_shown"] == true

        store.respond_to?(:warning) && store.warning ? store.warning : default_warning(store)
      end

      def default_warning(store)
        "the API key is stored in plaintext at #{store.location} with 0600 permissions; " \
          "install a keychain helper or set credential_store: keychain to avoid this warning"
      end

      def persist!(name, server_url, scopes, mode, warning_shown)
        changes = {
          "profiles" => {
            name => {
              "server_url" => server_url,
              "scopes" => scopes,
              "read_only" => !scopes.include?("read_write"),
              "credential_store" => mode.to_s,
              "plaintext_warning_shown" => warning_shown ? previously_warned?(name) : true
            }
          }
        }
        changes["default_profile"] = name if loader.load["default_profile"].nil?

        loader.save(changes)
      end

      def previously_warned?(name)
        stored_attributes(name)["plaintext_warning_shown"] == true
      end

      def rollback(store, key)
        store.delete(key)
        store.reset! if store.respond_to?(:reset!)
      rescue Errors::Error, SystemCallError
        nil
      end

      def now
        runtime.clock.respond_to?(:now) ? runtime.clock.now : runtime.clock
      end

      def tty?(io)
        io.respond_to?(:tty?) && io.tty?
      end

      def option(name)
        return nil unless options.respond_to?(:key?)

        if options.key?(name) && !options[name].nil?
          options[name]
        elsif options.key?(name.to_s)
          options[name.to_s]
        end
      end

      def present?(value)
        value.is_a?(String) && !value.empty?
      end

      def truthy?(value)
        value == true || value.to_s.match?(/\A(?:1|true|yes|on)\z/i)
      end
    end
  end
end

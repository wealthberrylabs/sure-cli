# frozen_string_literal: true

require "time"

require_relative "../auth/api_key_provider"
require_relative "../auth/store_factory"
require_relative "../cli/context"
require_relative "../cli/runtime"
require_relative "../config"
require_relative "../errors"
require_relative "../http/response"
require_relative "../http/url_builder"
require_relative "check"
require_relative "result"

module Sure
  module Doctor
    # Runs every diagnostic in order and never short-circuits. Checks that
    # depend on a failed prerequisite report SKIP rather than a second failure,
    # so the user sees one actionable problem and the rest of the checklist.
    class Runner
      CLOCK_SKEW_LIMIT = 300
      LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

      CHECKS = [
        Check.new(id: :config, label: "Config directory and file", run: :check_config),
        Check.new(id: :profile, label: "Profile and server URL", run: :check_profile),
        Check.new(id: :credential, label: "Credential present", run: :check_credential),
        Check.new(id: :connectivity, label: "Connectivity and TLS", run: :check_connectivity),
        Check.new(id: :authentication, label: "Authentication", run: :check_authentication),
        Check.new(id: :scope, label: "API key scope", run: :check_scope),
        Check.new(id: :capability, label: "Server capability", run: :check_capability),
        Check.new(id: :clock, label: "Clock skew", run: :check_clock),
        Check.new(id: :rate_limit, label: "Rate limit", run: :check_rate_limit)
      ].freeze

      EXIT_CODES = {
        config: 1,
        profile: 2,
        credential: 3,
        connectivity: 8,
        authentication: 3,
        scope: 3,
        capability: 8,
        clock: 1,
        rate_limit: 0
      }.freeze

      def initialize(runtime: Sure::CLI::Runtime.current, context: nil, clock: nil)
        @runtime = runtime
        @context = context || Sure::CLI::Context.new(runtime: runtime, options: {})
        @clock = clock
      end

      attr_reader :runtime, :context

      # Returns [Array<Result>, exit_code]. The first FAIL in check order wins.
      def run
        state = {}
        results = CHECKS.map do |check|
          result = send(check.run, state)
          state[check.id] = result
          result
        end

        failure = results.find(&:fail?)
        [ results, failure.nil? ? 0 : exit_code_for(failure, state) ]
      end

      private

      def check_config(state)
        paths = context.loader.paths
        directory = paths.directory
        file = paths.config_file

        unless File.directory?(directory)
          state[:config_ok] = false
          return fail(:config, "config directory #{directory} does not exist", "Run `sure auth login`")
        end
        if File.symlink?(directory)
          state[:config_ok] = false
          return fail(:config, "config directory #{directory} is a symlink", "Replace the symlink with a real 0700 directory")
        end

        directory_stat = File.stat(directory)
        if (directory_stat.mode & 0o077) != 0
          state[:config_ok] = false
          return fail(:config, "config directory #{directory} is group/world accessible",
                      "chmod 700 #{directory}")
        end
        if directory_stat.uid != Process.euid
          state[:config_ok] = false
          return fail(:config, "config directory #{directory} is not owned by the current user",
                      "chown #{Process.euid} #{directory}")
        end

        unless File.exist?(file)
          state[:config_ok] = false
          return fail(:config, "config file #{file} does not exist", "Run `sure auth login`")
        end
        if File.symlink?(file)
          state[:config_ok] = false
          return fail(:config, "config file #{file} is a symlink", "Replace the symlink with a real 0600 file")
        end

        file_stat = File.stat(file)
        if (file_stat.mode & 0o077) != 0
          state[:config_ok] = false
          return fail(:config, "config file #{file} is group/world accessible", "chmod 600 #{file}")
        end
        if file_stat.uid != Process.euid
          state[:config_ok] = false
          return fail(:config, "config file #{file} is not owned by the current user",
                      "chown #{Process.euid} #{file}")
        end

        state[:config_ok] = true
        pass(:config, "directory #{directory} is 0700 and #{file} is 0600")
      rescue SystemCallError => e
        state[:config_ok] = false
        fail(:config, "cannot inspect #{file}: #{e.message}", "Check permissions on #{directory}")
      end

      def check_profile(state)
        return skip(:profile, "config checks failed") unless state[:config_ok]

        profile = context.profile
        uri = HTTP::UrlBuilder.parse(profile.server_url)
        state[:profile] = profile
        state[:profile_ok] = true

        if uri.scheme.to_s.downcase == "http" && !loopback?(uri.host)
          warn(:profile, "profile `#{profile.name}` uses plain http to #{uri.host}",
               "Use https or a trusted private network; API keys can be intercepted")
        else
          pass(:profile, "profile `#{profile.name}` -> #{profile.server_url}")
        end
      rescue Errors::Error => e
        state[:profile_ok] = false
        fail(:profile, e.message,
             "Set a valid server URL with `sure auth login --server <url>` or SURE_SERVER")
      end

      def check_credential(state)
        return skip(:credential, "config or profile checks failed") unless state[:profile_ok]

        context.credential
        source = context.credential_source
        state[:credential_ok] = true

        if source == :environment
          pass(:credential, "SURE_API_KEY is set for this process")
        elsif context.store.mode == :file
          warn(:credential, "credential stored in #{context.store.location} (file, mode 0600)",
               "Install a keychain helper or set credential_store: keychain")
        else
          pass(:credential, "credential stored in the OS keychain")
        end
      rescue Errors::Error => e
        state[:credential_ok] = false
        fail(:credential, e.message, "Run `sure auth login` or set SURE_API_KEY")
      end

      def check_connectivity(state)
        return skip(:connectivity, "no usable credential") unless state[:credential_ok]

        usage = fetch_usage
        state[:usage] = usage

        if usage.is_a?(HTTP::Response)
          state[:reachable] = true
          return pass(:connectivity, "server reachable (HTTP #{usage.status})")
        end

        status = usage.http_status
        if [ 401, 403 ].include?(status)
          state[:reachable] = true
          return pass(:connectivity, "server reachable (HTTP #{status}; authentication failed)")
        end

        state[:reachable] = false
        fail(:connectivity, usage.message,
             "Verify the server URL and TLS settings, including the CA bundle")
      end

      def check_authentication(state)
        return skip(:authentication, "connectivity failed") unless state[:reachable]

        usage = state[:usage]
        if usage.is_a?(HTTP::Response) && usage.success?
          state[:authenticated] = true
          return pass(:authentication, "authenticated (HTTP #{usage.status})")
        end

        status = usage.http_status
        if [ 401, 403 ].include?(status)
          fail(:authentication, "the API key was rejected (HTTP #{status})",
               "Run `sure auth login` with a valid key")
        else
          skip(:authentication, "no authenticated response to inspect")
        end
      end

      def check_scope(state)
        return skip(:scope, "authentication failed") unless state[:authenticated]

        body = body_of(state[:usage])
        scopes = Array(body.dig("api_key", "scopes")).map(&:to_s).reject(&:empty?)
        state[:scopes] = scopes

        if scopes.empty?
          fail(:scope, "the server returned no scopes for this key",
               "Create a key in Sure Settings -> API Keys and run `sure auth login` again")
        elsif scopes.include?("read_write")
          pass(:scope, "read_write (includes read)")
        elsif scopes.include?("read")
          warn(:scope, "read-only key; write commands will be refused",
               "Create a read_write key in Sure Settings -> API Keys")
        else
          fail(:scope, "unrecognized scopes: #{scopes.join(', ')}",
               "Create a read or read_write key in Sure Settings -> API Keys")
        end
      end

      def check_capability(state)
        return skip(:capability, "authentication failed") unless state[:authenticated]

        response = context.client.get("/api/v1/accounts?per_page=1")
        body = body_of(response)
        if body["accounts"].is_a?(Array) && body["pagination"].is_a?(Hash)
          pass(:capability, "GET /api/v1/accounts returned the collection envelope")
        else
          fail(:capability, "GET /api/v1/accounts did not return accounts and pagination",
               "Upgrade Sure or verify the server is a complete /api/v1 deployment")
        end
      rescue Errors::Error => e
        state[:capability_exit] = 3 if e.http_status == 401
        fail(:capability, e.message,
             "Verify the server supports /api/v1/accounts and the key is still valid")
      end

      def check_clock(state)
        usage = state[:usage]
        return skip(:clock, "no response to read the Date header from") if usage.nil?

        headers = usage.headers
        raw = header_value(headers, "Date")
        return skip(:clock, "the server did not send a Date header") if raw.nil? || raw.to_s.empty?

        server_time = Time.httpdate(raw.to_s)
        skew = (server_time - now).abs.round
        if skew > CLOCK_SKEW_LIMIT
          fail(:clock, "server clock differs by #{skew}s (limit #{CLOCK_SKEW_LIMIT}s)",
               "Synchronize the CLI host and the Sure server clocks with NTP, then retry")
        else
          pass(:clock, "server clock differs by #{skew}s")
        end
      rescue ArgumentError
        skip(:clock, "the server Date header could not be parsed")
      end

      def check_rate_limit(state)
        return skip(:rate_limit, "authentication failed") unless state[:authenticated]

        body = body_of(state[:usage])
        rate = body["rate_limit"].is_a?(Hash) ? body["rate_limit"] : {}
        tier = rate["tier"] || state[:usage].rate_limit.tier
        limit = rate["limit"]
        remaining = rate["remaining"]

        if tier.to_s.downcase == "noop" || limit.nil?
          pass(:rate_limit, "unlimited (self-hosted noop tier)")
        elsif remaining.to_i <= 0
          warn(:rate_limit, "tier #{tier}: no requests remaining in this window",
               "Wait for the rate-limit window to reset")
        else
          pass(:rate_limit, "tier #{tier}: #{remaining}/#{limit} requests remaining")
        end
      end

      def fetch_usage
        context.client.get("/api/v1/usage")
      rescue Errors::Error => e
        e
      end

      def body_of(response)
        response.is_a?(HTTP::Response) && response.body.is_a?(Hash) ? response.body : {}
      end

      def header_value(headers, name)
        headers.each do |key, value|
          return value if key.to_s.casecmp?(name)
        end
        nil
      end

      def loopback?(host)
        LOOPBACK_HOSTS.include?(host.to_s.downcase.delete_prefix("[").delete_suffix("]"))
      end

      def now
        clock = @clock || runtime.clock
        clock.respond_to?(:now) ? clock.now : clock
      end

      def exit_code_for(result, state)
        return state[:capability_exit] || 8 if result.id.to_sym == :capability

        EXIT_CODES.fetch(result.id.to_sym, 1)
      end

      def pass(id, detail, fix = "None")
        result(id, :pass, detail, fix)
      end

      def warn(id, detail, fix)
        result(id, :warn, detail, fix)
      end

      def fail(id, detail, fix)
        result(id, :fail, detail, fix)
      end

      def skip(id, detail)
        result(id, :skip, detail, "No action needed")
      end

      def result(id, status, detail, fix)
        check = CHECKS.find { |entry| entry.id == id.to_sym }
        Result.new(id: id, label: check.label, status: status, detail: detail, fix: fix)
      end
    end
  end
end

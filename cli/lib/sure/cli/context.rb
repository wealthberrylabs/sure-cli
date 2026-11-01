# frozen_string_literal: true

require_relative "../auth/api_key_provider"
require_relative "../config"
require_relative "../http/url_builder"
require_relative "runtime"

module Sure
  module CLI
    # Resolves profile, server, TLS, output, and credential source exactly once
    # per command. Commands read this instead of inspecting argv or environment
    # themselves; the API key is only ever exposed through #api_key.
    class Context
      def self.current(runtime = Runtime.current, options: {}, store: nil)
        new(runtime: runtime, options: options, store: store)
      end

      def initialize(runtime:, options: {}, store: nil)
        @runtime = runtime
        @options = options || {}
        @store = store
        @loader = Config::Loader.new(paths: Config::Paths.new(env: runtime.env))
        @resolver = Config::Resolver.new(
          env: runtime.env,
          options: @options,
          loader: @loader,
          cwd: runtime.cwd,
          stderr: runtime.stderr
        )
      end

      attr_reader :runtime, :options, :loader, :resolver

      def profile
        @profile ||= resolver.resolve
      end

      def store
        @store ||= Auth::NullStore.new
      end

      def url_builder
        @url_builder ||= HTTP::UrlBuilder.new(profile.server_url, stderr: runtime.stderr)
      end

      def output_format
        @output_format ||= profile.output || (tty? ? :table : :json)
      end

      # [secret, :environment | :store]; normally used through #api_key.
      def credential
        @credential ||= Auth::ApiKeyProvider.new(env: runtime.env, store: store).fetch(profile)
      end

      def api_key
        credential.first
      end

      # :environment, :keychain, or :file.
      def credential_source
        @credential_source ||= credential.last == :environment ? :environment : store.mode
      end

      # Environment keys can change between commands, so cached scopes from the
      # profile must not be trusted for them (enforced by Plan 01-04).
      def scopes_trusted?
        credential_source != :environment
      end

      def inspect
        "#<Sure::CLI::Context profile=#{@profile&.name.inspect} " \
          "credential_source=#{@credential_source.inspect} api_key=[REDACTED] " \
          "output_format=#{@output_format.inspect}>"
      end

      private

      def tty?
        runtime.stdout.respond_to?(:tty?) && runtime.stdout.tty?
      end
    end
  end
end

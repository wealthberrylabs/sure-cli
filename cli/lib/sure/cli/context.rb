# frozen_string_literal: true

require_relative "../config"
require_relative "../http/url_builder"
require_relative "runtime"

module Sure
  module CLI
    # Resolves profile, server, TLS, output, and (with Plan 01-02's provider)
    # credential source exactly once per command. Commands read this instead of
    # inspecting argv or environment themselves.
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

      def url_builder
        @url_builder ||= HTTP::UrlBuilder.new(profile.server_url, stderr: runtime.stderr)
      end

      def output_format
        @output_format ||= profile.output || (tty? ? :table : :json)
      end

      def inspect
        "#<Sure::CLI::Context profile=#{@profile&.name.inspect} " \
          "output_format=#{@output_format.inspect}>"
      end

      private

      def tty?
        runtime.stdout.respond_to?(:tty?) && runtime.stdout.tty?
      end
    end
  end
end

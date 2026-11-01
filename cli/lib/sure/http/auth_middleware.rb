# frozen_string_literal: true

require "faraday"
require "uri"

require_relative "../errors"

module Sure
  module HTTP
    # Injects exactly one credential header, and only for the resolved server.
    # There is deliberately no way to supply a custom header from argv.
    class AuthMiddleware < Faraday::Middleware
      HEADER = "X-Api-Key"

      def initialize(app, auth_provider, profile, redactor = nil)
        super(app)
        @auth_provider = auth_provider
        @profile = profile
        @redactor = redactor
        @secret = nil
        @origin = nil
      end

      def call(env)
        ensure_same_origin!(env.url)
        env.request_headers[HEADER] = secret
        @app.call(env)
      end

      private

      def secret
        @secret ||= begin
          value = @auth_provider.fetch(@profile).first.to_s
          @redactor&.register(value)
          value
        end
      end

      # Refuse to send the key anywhere except the configured server origin,
      # even if a future caller passes an absolute URL by mistake.
      def ensure_same_origin!(url)
        return if same_origin?(url)

        raise Sure::Errors::UsageError,
              "refusing to send the API key to #{url.host.inspect}; expected #{expected_origin}"
      end

      def same_origin?(url)
        return false unless url.is_a?(URI::Generic)

        origin_of(url) == expected_origin
      end

      def expected_origin
        @origin ||= begin
          server = URI.parse(@profile.server_url.to_s)
          origin_of(server)
        end
      end

      def origin_of(uri)
        default_port = uri.scheme.to_s.downcase == "https" ? 443 : 80
        port_suffix = uri.port == default_port ? "" : ":#{uri.port}"
        "#{uri.scheme.to_s.downcase}://#{uri.host&.downcase}#{port_suffix}"
      end
    end
  end
end

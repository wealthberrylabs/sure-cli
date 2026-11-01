# frozen_string_literal: true

require "uri"

require_relative "../errors"

module Sure
  module HTTP
    # Joins the server base URL (which may carry a path prefix such as `/sure`)
    # with API paths without letting URI.join drop the prefix.
    #
    #   UrlBuilder.new("https://host/sure").join("/api/v1/usage")
    #   # => "https://host/sure/api/v1/usage"
    class UrlBuilder
      SCHEMES = %w[http https].freeze
      LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
      API_PREFIX = %r{(?:\A|/)api(?:/v1)?\z}

      # Structural validation shared by the resolver and the constructor. Does
      # not emit warnings, so validation is idempotent.
      def self.parse(server_url)
        raw = server_url.to_s
        raise Errors::UsageError, "server URL is required" if raw.strip.empty?

        uri = parse_uri(raw)
        validate_scheme!(uri, raw)
        validate_host!(uri, raw)
        validate_no_userinfo!(uri)
        validate_no_query_or_fragment!(uri, raw)
        validate_not_api_prefix!(uri, raw)
        uri
      end

      def self.parse_uri(raw)
        URI.parse(raw)
      rescue URI::InvalidURIError => e
        raise Errors::UsageError, "invalid server URL: #{e.message}"
      end

      def self.validate_scheme!(uri, raw)
        scheme = uri.scheme&.downcase
        return if SCHEMES.include?(scheme)

        raise Errors::UsageError, "server URL must use http or https: #{raw.inspect}"
      end

      def self.validate_host!(uri, raw)
        return if uri.host && !uri.host.empty?

        raise Errors::UsageError, "server URL must include a host: #{raw.inspect}"
      end

      def self.validate_no_userinfo!(uri)
        return unless uri.userinfo

        raise Errors::UsageError, "server URL must not include credentials (userinfo)"
      end

      def self.validate_no_query_or_fragment!(uri, raw)
        return unless uri.query || uri.fragment

        raise Errors::UsageError, "server URL must not include a query or fragment: #{raw.inspect}"
      end

      def self.validate_not_api_prefix!(uri, raw)
        path = uri.path.to_s.sub(%r{/+\z}, "")
        return unless path.match?(API_PREFIX)

        raise Errors::UsageError,
              "server URL must be the base URL without the /api or /api/v1 prefix: #{raw.inspect}"
      end

      private_class_method :parse_uri, :validate_scheme!, :validate_host!,
                           :validate_no_userinfo!, :validate_no_query_or_fragment!,
                           :validate_not_api_prefix!

      def initialize(server_url, stderr: nil)
        @uri = self.class.parse(server_url)
        @prefix = normalize_path(@uri.path)
        @stderr = stderr
        warn_insecure_transport
      end

      attr_reader :uri

      def scheme
        uri.scheme.downcase
      end

      def host
        uri.host
      end

      def port
        uri.port
      end

      # Origin without the default port, used for credential key fingerprints.
      def origin
        default_port = scheme == "https" ? 443 : 80
        port_suffix = port == default_port ? "" : ":#{port}"
        "#{scheme}://#{host}#{port_suffix}"
      end

      def base_url
        "#{origin}#{@prefix}"
      end

      def join(path, query: nil)
        segments = path.to_s.split("/").reject(&:empty?)
        suffix = segments.empty? ? "" : "/#{segments.join('/')}"
        combined = "#{@prefix}#{suffix}"
        combined = "/" if combined.empty?

        url = "#{origin}#{combined}"
        url = "#{url}?#{URI.encode_www_form(query)}" if query && !query.empty?
        url
      end

      private

      def normalize_path(path)
        segments = path.to_s.split("/").reject(&:empty?)
        segments.empty? ? "" : "/#{segments.join('/')}"
      end

      def warn_insecure_transport
        return unless scheme == "http"
        return if loopback_host?
        return unless @stderr

        @stderr.puts("warning: using plain http to #{host}; credentials can be intercepted")
      end

      def loopback_host?
        normalized = host.downcase.delete_prefix("[").delete_suffix("]")
        LOOPBACK_HOSTS.include?(normalized)
      end
    end
  end
end

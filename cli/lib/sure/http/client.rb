# frozen_string_literal: true

require "uri"

require_relative "../errors"
require_relative "../errors/mapper"
require_relative "../redactor"
require_relative "connection"
require_relative "response"

module Sure
  module HTTP
    # One request through the shared pipeline. Commands never build a Faraday
    # connection themselves, and no response body or header is ever logged.
    class Client
      def initialize(profile:, auth_provider:, url_builder:, runtime:,
                     connection: nil, redactor: nil, verbose: false)
        @profile = profile
        @auth_provider = auth_provider
        @url_builder = url_builder
        @runtime = runtime
        @redactor = redactor || Sure::Redactor.new
        @verbose = verbose
        @connection = connection || Connection.build(
          profile: profile,
          auth_provider: auth_provider,
          redactor: @redactor
        )
      end

      attr_reader :profile, :url_builder, :redactor, :connection

      def get(path, query: nil)
        request("GET", path, query: query)
      end

      def request(method, path, body: nil, query: nil)
        verb = method.to_s.upcase
        url = build_url(path, query: query)
        started = monotonic

        faraday_response = @connection.run_request(verb.downcase.to_sym, url, body, nil)
        duration = monotonic - started
        response = build_response(faraday_response, duration)

        log_verbose(verb, url, response)
        ensure_success!(response)
        response
      rescue Sure::Errors::Error
        raise
      rescue StandardError => e
        raise Sure::Errors::Mapper.map(e, redactor: @redactor)
      end

      private

      def build_url(path, query: nil)
        raw = path.to_s
        if raw.include?("?")
          api_path, embedded_query = raw.split("?", 2)
          url = @url_builder.join(api_path)
          return url if embedded_query.nil? || embedded_query.empty?

          "#{url}?#{embedded_query}"
        else
          @url_builder.join(raw, query: query)
        end
      end

      def build_response(faraday_response, duration)
        Response.new(
          status: faraday_response.status,
          body: faraday_response.body,
          raw_body: faraday_response.env[:raw_body],
          headers: faraday_response.headers,
          duration: duration
        )
      end

      def ensure_success!(response)
        return if response.success?

        raise Sure::Errors::Mapper.map_response(
          status: response.status,
          body: response.body,
          headers: response.headers,
          redactor: @redactor
        )
      end

      # Method, path without query, status, duration, and request ID only.
      # Headers and bodies must never appear here.
      def log_verbose(verb, url, response)
        return unless @verbose

        path = URI.parse(url).path
        message = "#{verb} #{path} #{response.status} " \
                  "#{(response.duration * 1000).round}ms " \
                  "request_id=#{response.request_id || '-'}"
        @runtime.stderr.puts(@redactor.redact_value(message))
      rescue URI::InvalidURIError
        @runtime.stderr.puts(@redactor.redact_value("#{verb} #{response.status}"))
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "rate_limit"

module Sure
  module HTTP
    # Immutable view of one server response. Commands receive this instead of
    # touching Faraday envelopes, so response details stay one contract.
    class Response
      EMPTY_BODY = ""

      attr_reader :status, :body, :raw_body, :headers, :request_id, :rate_limit, :duration

      def initialize(status:, body: nil, raw_body: nil, headers: nil, duration: 0.0)
        @status = status.to_i
        @body = body
        @raw_body = raw_body.nil? ? body.to_s : raw_body.to_s
        @headers = headers || {}
        @request_id = extract_request_id(@headers)
        @rate_limit = RateLimit.parse(@headers)
        @duration = duration.to_f
        freeze
      end

      def success?
        status.between?(200, 299)
      end

      def empty?
        raw_body.nil? || raw_body.empty?
      end

      def header(name)
        return headers[name] if headers.key?(name)

        headers.each do |key, value|
          return value if key.to_s.casecmp?(name)
        end
        nil
      end

      def inspect
        "#<Sure::HTTP::Response status=#{status} request_id=#{request_id.inspect} " \
          "duration=#{duration.round(3)}>"
      end

      alias_method :to_s, :inspect

      private

      def extract_request_id(headers)
        %w[X-Request-Id X-Request-ID Request-Id].each do |name|
          value = header(name)
          return value unless value.nil? || value.to_s.empty?
        end
        nil
      end
    end
  end
end

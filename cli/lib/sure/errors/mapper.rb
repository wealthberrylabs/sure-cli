# frozen_string_literal: true

require "json"
require "openssl"
require "thor"
require "timeout"

require "faraday"

require_relative "../errors"
require_relative "../redactor"

module Sure
  module Errors
    # The only place that turns an HTTP status or a transport exception into a
    # semantic exit code (D-13). Server-controlled text is redacted here so an
    # upstream body can never echo a credential.
    class Mapper
      TIMEOUT_STATUSES = [ 408, 504 ].freeze
      AUTHENTICATION_STATUSES = [ 401, 403 ].freeze
      VALIDATION_STATUSES = [ 400, 409, 422 ].freeze

      REDIRECT_HINT = "redirects are not followed; check the server URL"

      def self.map(error, redactor: nil)
        new(redactor).map(error)
      end

      def self.map_response(status:, body: nil, headers: nil, redactor: nil)
        new(redactor).map_response(status: status, body: body, headers: headers)
      end

      def initialize(redactor = nil)
        @redactor = redactor || Sure::Redactor.new
      end

      def map(error)
        case error
        when Sure::Errors::Error
          error
        when Faraday::TimeoutError, Timeout::Error, Errno::ETIMEDOUT
          timeout_error(error)
        when Faraday::ParsingError, JSON::ParserError
          network_error("the server returned a malformed response; try again or run `sure doctor`")
        when Faraday::ConnectionFailed
          connection_error(error)
        when Faraday::SSLError, OpenSSL::SSL::SSLError, SocketError, SystemCallError, EOFError
          network_error(error.message)
        when Faraday::ClientError, Faraday::ServerError
          map_faraday_error(error)
        when Thor::Error
          Sure::Errors::UsageError.new(redact(error.message))
        else
          Sure::Errors::GeneralError.new(redact(error.message))
        end
      end

      def map_response(status:, body: nil, headers: nil)
        status = status.to_i
        headers = headers || {}
        body = parsed_body(body)
        request_id = header(headers, "X-Request-Id")
        details = response_details(body)

        error_class = error_class_for(status)
        message = response_message(status, body)

        error_class.new(
          message,
          details: details,
          request_id: request_id,
          http_status: status,
          headers: headers
        )
      end

      private

      def error_class_for(status)
        return Sure::Errors::AuthenticationError if AUTHENTICATION_STATUSES.include?(status)
        return Sure::Errors::NotFoundError if status == 404
        return Sure::Errors::ValidationError if VALIDATION_STATUSES.include?(status)
        return Sure::Errors::RateLimitedError if status == 429
        return Sure::Errors::TimeoutError if TIMEOUT_STATUSES.include?(status)

        Sure::Errors::NetworkError
      end

      def response_message(status, body)
        server_message = extract_message(body)

        case status
        when 401
          "authentication failed (401): #{server_message || 'the API key is invalid, expired, or missing'}; " \
            "run `sure auth login` or set SURE_API_KEY"
        when 403
          "insufficient permissions (403): #{server_message || 'this key cannot perform that action'}; " \
            "create a read_write key in Sure Settings -> API Keys"
        when 404
          "not found (404): #{server_message || 'the requested resource does not exist'}"
        when 400, 409, 422
          "validation failed (#{status}): #{server_message || 'the server rejected the request'}"
        when 429
          rate_limit_message(server_message)
        when 408, 504
          "request timed out (#{status}): #{server_message || 'the server did not respond in time'}"
        when 300..399
          "unexpected redirect (#{status}): #{REDIRECT_HINT}"
        when 500..599
          "server error (#{status}); try again later or run `sure doctor`"
        else
          "unexpected HTTP status (#{status})#{": #{server_message}" if server_message}"
        end
      end

      def rate_limit_message(server_message)
        message = "rate limited (429): #{server_message || 'too many requests'}"
        message
      end

      def extract_message(body)
        return nil unless body.is_a?(Hash)

        message = body["message"] || body[:message]
        return nil if message.nil?

        redact(message.to_s)
      end

      def response_details(body)
        return nil unless body.is_a?(Hash)

        details = body["details"] || body[:details]
        return redact_details(details) if details.is_a?(Hash)

        errors = body["errors"] || body[:errors]
        return { "errors" => redact_details(errors) } unless errors.nil?

        nil
      end

      def map_faraday_error(error)
        response = error.respond_to?(:response) ? error.response : nil
        if response.is_a?(Hash) && response[:status]
          map_response(
            status: response[:status],
            body: response[:body],
            headers: response[:headers]
          )
        else
          network_error(error.message)
        end
      end

      def timeout_error(error)
        message = redact(error.message)
        message = "request timed out" if message.to_s.strip.empty?
        Sure::Errors::TimeoutError.new(message)
      end

      # Some adapters wrap a socket timeout as ConnectionFailed ("execution
      # expired"); keep those on exit 9 instead of reporting a network failure.
      def connection_error(error)
        message = error.message.to_s
        return timeout_error(error) if message.match?(/timed? ?out|timeout|execution expired/i)

        network_error(error)
      end

      def network_error(message)
        text = redact(message.to_s)
        text = "could not reach the server; check the server URL and TLS settings" if text.strip.empty?
        Sure::Errors::NetworkError.new(text)
      end

      def parsed_body(body)
        return body if body.is_a?(Hash) || body.nil?
        return body unless body.is_a?(String)

        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def redact(value)
        @redactor.redact_value(value)
      end

      def redact_details(value)
        @redactor.redact_tree(value)
      end

      def header(headers, name)
        return headers[name] if headers.is_a?(Hash) && headers.key?(name)

        headers.each do |key, value|
          return value if key.to_s.casecmp?(name)
        end
        nil
      end
    end
  end
end

# frozen_string_literal: true

require_relative "exit_codes"

module Sure
  module Errors
    # Base class for every expected CLI failure. Commands raise these; only the
    # process boundary (Sure::CLI::Runner) renders them and chooses an exit code.
    class Error < StandardError
      attr_reader :details, :request_id, :http_status, :headers

      def initialize(message = nil, details: nil, request_id: nil, http_status: nil, headers: nil)
        super(message)
        @details = details
        @request_id = request_id
        @http_status = http_status
        @headers = headers || {}
      end

      def exit_code
        ExitCodes::GENERAL
      end
    end

    class GeneralError < Error
      def exit_code
        ExitCodes::GENERAL
      end
    end

    class UsageError < Error
      def exit_code
        ExitCodes::USAGE
      end
    end

    class AuthenticationError < Error
      def exit_code
        ExitCodes::AUTHENTICATION
      end
    end

    class InsufficientScopeError < AuthenticationError
    end

    class NotFoundError < Error
      def exit_code
        ExitCodes::NOT_FOUND
      end
    end

    class ValidationError < Error
      def exit_code
        ExitCodes::VALIDATION
      end
    end

    class RateLimitedError < Error
      def exit_code
        ExitCodes::RATE_LIMITED
      end
    end

    class PartialFailureError < Error
      def exit_code
        ExitCodes::PARTIAL_FAILURE
      end
    end

    class NetworkError < Error
      def exit_code
        ExitCodes::NETWORK
      end
    end

    class TimeoutError < Error
      def exit_code
        ExitCodes::TIMEOUT
      end
    end
  end
end

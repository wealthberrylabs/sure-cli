# frozen_string_literal: true

require "faraday"
require "faraday/retry"

require_relative "../version"
require_relative "auth_middleware"

module Sure
  module HTTP
    # Builds the one Faraday pipeline every command uses. Never add a logger, a
    # redirect follower, or a second auth mechanism here.
    #
    # Declaration order matters: the retry middleware must wrap the JSON and
    # raise-error response handlers, otherwise raise_error raises on the first
    # 503 and the retry policy never sees the status.
    module Connection
      RETRY_STATUSES = [ 429, 502, 503, 504 ].freeze
      RETRY_METHODS = %i[get head].freeze

      def self.build(profile:, auth_provider:, redactor: nil)
        Faraday.new do |connection|
          connection.headers["User-Agent"] = "sure-cli/#{Sure::VERSION}"
          connection.headers["Accept"] = "application/json"

          connection.response :raise_error, include_request: false

          connection.request :json
          connection.request :retry,
            max: 2,
            interval: 0.5,
            interval_randomness: 0.5,
            backoff_factor: 2,
            max_interval: 10,
            retry_statuses: RETRY_STATUSES,
            methods: RETRY_METHODS,
            rate_limit_retry_header: "Retry-After",
            rate_limit_reset_header: "X-RateLimit-Reset"

          connection.use AuthMiddleware, auth_provider, profile, redactor

          connection.response :json,
            content_type: /\bjson$/,
            preserve_raw: true,
            parser_options: { allow_nan: true }

          connection.adapter :net_http

          connection.options.open_timeout = profile.open_timeout
          connection.options.timeout = profile.read_timeout
          connection.ssl.verify = profile.tls_verify
          connection.ssl.ca_file = profile.ca_bundle if profile.ca_bundle
        end
      end
    end
  end
end

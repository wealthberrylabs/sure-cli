# frozen_string_literal: true

module Sure
  module HTTP
    # Parses Sure's rate-limit headers. Reset values are seconds remaining (not
    # Unix epochs); missing headers, "Infinity", and self-hosted "noop" tiers
    # are all tolerated.
    RateLimit = Data.define(:limit, :remaining, :reset_in_seconds, :retry_after, :tier) do
      HEADER_LIMIT = "x-ratelimit-limit"
      HEADER_REMAINING = "x-ratelimit-remaining"
      HEADER_RESET = "x-ratelimit-reset"
      HEADER_RETRY_AFTER = "retry-after"
      UNLIMITED_VALUES = %w[infinity noop unlimited].freeze

      def self.parse(headers = nil, tier: nil)
        normalized = normalize_headers(headers)

        new(
          limit: integer(normalized[HEADER_LIMIT]),
          remaining: integer(normalized[HEADER_REMAINING]),
          reset_in_seconds: integer(normalized[HEADER_RESET]),
          retry_after: integer(normalized[HEADER_RETRY_AFTER]),
          tier: tier&.to_s
        )
      end

      def self.integer(value)
        text = value.to_s.strip
        return nil if text.empty?
        return nil if UNLIMITED_VALUES.include?(text.downcase)

        number = Integer(text, 10)
        number.negative? ? 0 : number
      rescue ArgumentError, TypeError
        nil
      end

      def self.normalize_headers(headers)
        return {} if headers.nil?

        headers.each_with_object({}) do |(key, value), result|
          result[key.to_s.downcase] = value
        end
      end

      private_class_method :normalize_headers

      # A self-hosted instance with the noop limiter reports no limit.
      def unlimited?
        limit.nil? || tier.to_s.downcase == "noop"
      end

      def reset?
        !reset_in_seconds.nil? || !retry_after.nil?
      end

      # Header values only; body-only fields such as tier are merged by callers.
      def to_h
        {
          "limit" => limit,
          "remaining" => remaining,
          "reset_in_seconds" => reset_in_seconds,
          "tier" => tier
        }.compact
      end
    end
  end
end

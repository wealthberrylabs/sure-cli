# frozen_string_literal: true

module Sure
  module Auth
    # A single stored credential. Data's default inspect would render the
    # secret, so both #inspect and #to_s are overridden to redact it.
    Credential = Data.define(:kind, :secret, :server_url, :created_at) do
      def inspect
        "#<Sure::Auth::Credential kind=#{kind.inspect} secret=[REDACTED] " \
          "server_url=#{server_url.inspect} created_at=#{created_at.inspect}>"
      end

      alias_method :to_s, :inspect
    end
  end
end

# frozen_string_literal: true

require_relative "../errors"

module Sure
  module CLI
    # Placeholder for the config/profile/credential resolver that lands with the
    # config plan. Requesting a context before then fails with exit code 2 rather
    # than silently using defaults.
    class Context
      MESSAGE = "profile configuration is not available until its plan lands"

      def self.current(*)
        raise Errors::UsageError, MESSAGE
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"

module Sure
  module CLI
    module Commands
      # Shell completion generation. Scripts land with the completion plan.
      class Completion < Sure::CLI::Base
        no_commands do
          def call(shell)
            raise Sure::Errors::UsageError, NOT_IMPLEMENTED
          end
        end
      end
    end
  end
end

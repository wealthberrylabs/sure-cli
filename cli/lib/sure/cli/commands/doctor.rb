# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"

module Sure
  module CLI
    module Commands
      # Diagnostics command. Checks land with the doctor plan.
      class Doctor < Sure::CLI::Base
        no_commands do
          def call
            raise Sure::Errors::UsageError, NOT_IMPLEMENTED
          end
        end
      end
    end
  end
end

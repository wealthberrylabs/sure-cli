# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"

module Sure
  module CLI
    module Commands
      # Raw /api/v1 escape hatch. Implementation (path validation, confirmation,
      # redaction) lands with the HTTP/API plan.
      class Api < Sure::CLI::Base
        no_commands do
          def call(method, path)
            raise Sure::Errors::UsageError, NOT_IMPLEMENTED
          end
        end
      end
    end
  end
end

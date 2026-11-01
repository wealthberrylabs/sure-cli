# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"
require_relative "../../completion/generator"

module Sure
  module CLI
    module Commands
      # Writes one catalog-derived completion script to stdout. It makes no
      # network calls and never resolves config or credentials.
      class Completion < Sure::CLI::Base
        no_commands do
          def call(shell)
            runtime.stdout.write(Sure::Completion::Generator.new.render(shell))
          end
        end
      end
    end
  end
end

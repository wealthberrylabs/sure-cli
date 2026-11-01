# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"
require_relative "../../doctor/runner"
require_relative "../../errors"
require_relative "../../output/result"
require_relative "../../output/selector"

module Sure
  module CLI
    module Commands
      # Diagnostics command. It deliberately does not resolve the profile before
      # starting the runner: a missing or broken config must become a Check 1
      # FAIL, not an uncaught usage error.
      class Doctor < Sure::CLI::Base
        no_commands do
          def call
            results, code = Sure::Doctor::Runner.new(runtime: runtime).run

            Output::Selector.new(
              options: options,
              env: runtime.env,
              profile: nil,
              stdout: runtime.stdout,
              stderr: runtime.stderr,
              clock: runtime.clock
            ).render(Output::Result.new(data: { "checks" => results.map(&:to_h) }))

            raise Sure::Errors::ExitStatusError.new(code) unless code.zero?
          end
        end
      end
    end
  end
end

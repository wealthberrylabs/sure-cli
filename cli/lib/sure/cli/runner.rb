# frozen_string_literal: true

require "thor"

require_relative "../errors"
require_relative "application"
require_relative "runtime"
require_relative "shell"

module Sure
  module CLI
    # The single process boundary. Parses argv, installs the runtime, and turns
    # every expected failure into one stderr line plus a semantic exit code.
    class Runner
      FORBIDDEN_OPTION = "--api-key"
      FORBIDDEN_MESSAGE =
        "the --api-key flag is not supported; " \
        "use --api-key-file, --api-key-stdin, or SURE_API_KEY"

      def initialize(stdin:, stdout:, stderr:, env:, cwd:, clock:)
        @runtime = Runtime.new(
          stdin: stdin, stdout: stdout, stderr: stderr,
          env: env, cwd: cwd, clock: clock
        )
      end

      attr_reader :runtime

      def call(argv)
        Runtime.with(runtime) do
          reject_forbidden_api_key(argv)
          Application.start(argv, debug: true, shell: Shell.new(runtime))
        end
        Errors::ExitCodes::SUCCESS
      rescue Errors::Error => e
        render(e.message)
        e.exit_code
      rescue Thor::Error => e
        render(e.message)
        Errors::ExitCodes::USAGE
      rescue Interrupt
        Errors::ExitCodes::INTERRUPTED
      rescue Errno::EPIPE
        Errors::ExitCodes::SUCCESS
      end

      private

      # Reject the forbidden argv flag before Thor parses argv, and never echo
      # the supplied value.
      def reject_forbidden_api_key(argv)
        argv.each do |token|
          next unless token.is_a?(String)

          if token == FORBIDDEN_OPTION || token.start_with?("#{FORBIDDEN_OPTION}=")
            raise Errors::UsageError, FORBIDDEN_MESSAGE
          end
        end
      end

      # Collapse a possibly multi-line Thor message into one line. Expected
      # failures never print a Ruby backtrace.
      def render(message)
        line = message.to_s.lines.map(&:strip).reject(&:empty?).join(" ")
        runtime.stderr.puts(line) unless line.empty?
      end
    end
  end
end

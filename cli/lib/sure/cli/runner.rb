# frozen_string_literal: true

require "json"
require "thor"

require_relative "../errors"
require_relative "../redactor"
require_relative "application"
require_relative "runtime"
require_relative "shell"

module Sure
  module CLI
    # The single process boundary. Parses argv, installs the runtime, and turns
    # every expected failure into one stderr line (or one JSON object in machine
    # mode) plus a semantic exit code. Credentials are redacted here too.
    class Runner
      FORBIDDEN_OPTION = "--api-key"
      FORBIDDEN_MESSAGE =
        "the --api-key flag is not supported; " \
        "use --api-key-file, --api-key-stdin, or SURE_API_KEY"
      ACTIVE_SECRET_ENV = "SURE_API_KEY"

      GLOBAL_VALUE_OPTIONS = %w[--profile --server --ca-bundle --fields].freeze
      GLOBAL_BOOLEAN_OPTIONS = %w[
        --json --table --csv --ndjson --quiet --verbose
        --color --no-color --insecure --no-insecure
      ].freeze
      TERMINAL_OPTIONS = %w[--version -v --help -h].freeze

      ERROR_SLUGS = {
        "Sure::Errors::UsageError" => "usage_error",
        "Sure::Errors::AuthenticationError" => "authentication_error",
        "Sure::Errors::InsufficientScopeError" => "insufficient_scope",
        "Sure::Errors::NotFoundError" => "not_found",
        "Sure::Errors::ValidationError" => "validation_error",
        "Sure::Errors::RateLimitedError" => "rate_limited",
        "Sure::Errors::PartialFailureError" => "partial_failure",
        "Sure::Errors::NetworkError" => "network_error",
        "Sure::Errors::TimeoutError" => "timeout",
        "Sure::Errors::GeneralError" => "general_error"
      }.freeze

      def initialize(stdin:, stdout:, stderr:, env:, cwd:, clock:)
        @runtime = Runtime.new(
          stdin: stdin, stdout: stdout, stderr: stderr,
          env: env, cwd: cwd, clock: clock
        )
      end

      attr_reader :runtime

      def call(argv)
        @machine_output = machine_output?(argv)

        Runtime.with(runtime) do
          reject_forbidden_api_key(argv)
          Application.start(normalize_global_options(argv), debug: true, shell: Shell.new(runtime))
        end
        Errors::ExitCodes::SUCCESS
      rescue Errors::Error => e
        render_error(e)
        e.exit_code
      rescue Thor::Error => e
        render_usage_error(e)
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

      # Thor resolves the command name from the first token, so a documented
      # class option written before the command is mistaken for a command name.
      # Move the leading run of known global options behind the command and its
      # arguments, where Thor already accepts them, and reject anything else
      # loudly instead of degrading to help. A bare `--` disables normalization
      # so terminator arguments keep their original order.
      def normalize_global_options(argv)
        leading = []
        index = 0

        while index < argv.length
          token = argv[index]
          break unless token.is_a?(String) && token.start_with?("-")
          return argv if token == "--"

          if TERMINAL_OPTIONS.include?(token)
            # Version and help must stay the first token for Thor to map them;
            # keep any options collected ahead of them beside the terminal.
            return argv if leading.empty?

            return [ token ] + leading + (argv[(index + 1)..] || [])
          end

          name, inline_value = token.split("=", 2)

          if GLOBAL_VALUE_OPTIONS.include?(name)
            if inline_value.nil?
              value = argv[index + 1]
              if value.nil? || (value.is_a?(String) && value.start_with?("-"))
                raise Errors::UsageError,
                      "missing value for #{name}; pass #{name} VALUE or #{name}=VALUE"
              end

              leading << token << value
              index += 2
            else
              leading << token
              index += 1
            end
          elsif GLOBAL_BOOLEAN_OPTIONS.include?(name)
            leading << token
            index += 1
          else
            raise Errors::UsageError,
                  "unknown global option #{name}; global options may appear " \
                  "before or after the command but must be valid"
          end
        end

        rest = argv[index..] || []
        return argv if leading.empty? || rest.empty?

        rest + leading
      end

      def machine_output?(argv)
        return true if argv.include?("--json")

        !tty?(runtime.stdout)
      end

      def tty?(io)
        io.respond_to?(:tty?) && io.tty?
      end

      def redactor
        @redactor ||= Redactor.new(active_secret: runtime.env[ACTIVE_SECRET_ENV])
      end

      def render_error(error)
        return if error.respond_to?(:silent?) && error.silent?

        message = redactor.redact_value(error.message.to_s)

        if @machine_output
          runtime.stderr.puts(JSON.generate(
            error: ERROR_SLUGS.fetch(error.class.name, "general_error"),
            message: collapse(message),
            details: redact_details(error.details),
            request_id: error.request_id,
            http_status: error.http_status,
            exit_code: error.exit_code
          ))
        else
          line = collapse(message)
          runtime.stderr.puts("error: #{line}") unless line.empty?
        end
      end

      def render_usage_error(error)
        message = redactor.redact_value(error.message.to_s)

        if @machine_output
          runtime.stderr.puts(JSON.generate(
            error: "usage_error",
            message: collapse(message),
            details: nil,
            request_id: nil,
            http_status: nil,
            exit_code: Errors::ExitCodes::USAGE
          ))
        else
          line = collapse(message)
          runtime.stderr.puts("error: #{line}") unless line.empty?
        end
      end

      # Collapse a possibly multi-line message into one line. Expected failures
      # never print a Ruby backtrace.
      def collapse(message)
        message.to_s.lines.map(&:strip).reject(&:empty?).join(" ")
      end

      def redact_details(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key.to_s] = redact_details(item) }
        when Array
          value.map { |item| redact_details(item) }
        when String
          redactor.redact_value(value)
        else
          value
        end
      end
    end
  end
end

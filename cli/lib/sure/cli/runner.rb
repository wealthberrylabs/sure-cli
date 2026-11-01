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
          Application.start(argv, debug: true, shell: Shell.new(runtime))
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

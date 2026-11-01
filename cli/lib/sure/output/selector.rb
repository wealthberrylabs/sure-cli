# frozen_string_literal: true

require_relative "../errors"
require_relative "json"
require_relative "table"

module Sure
  module Output
    # Chooses one formatter for the command. Precedence is explicit flags,
    # SURE_OUTPUT, the profile's output setting, then TTY detection (D-11).
    # CSV/NDJSON/--fields belong to Plan 01-05 and are not accepted here yet.
    class Selector
      FORMATS = %i[json table].freeze
      UNSUPPORTED_OPTIONS = %i[csv ndjson fields].freeze

      def initialize(options: {}, env: {}, profile: nil, stdout: $stdout, stderr: nil, clock: Time)
        @options = options || {}
        @env = env || {}
        @profile = profile
        @stdout = stdout
        @stderr = stderr
        @clock = clock
      end

      attr_reader :options, :env, :profile, :stdout, :stderr, :clock

      def format
        @format ||= resolve_format
      end

      def formatter
        @formatter ||= case format
        when :json then Json.new(clock: clock)
        when :table then Table.new(color: color?)
        end
      end

      def render(result, fields: nil)
        formatter.render(result, io: stdout, stderr: stderr, fields: fields)
      end

      def color?
        return false unless tty?
        return false if option(:color) == false || option(:color) == "false"
        return false if env.key?("NO_COLOR")
        return false if env["TERM"].to_s.downcase == "dumb"

        true
      end

      def quiet?
        truthy?(option(:quiet))
      end

      def verbose?
        truthy?(option(:verbose))
      end

      def tty?
        stdout.respond_to?(:tty?) && stdout.tty?
      end

      private

      def resolve_format
        json = truthy?(option(:json))
        table = truthy?(option(:table))

        raise Errors::UsageError, "--json and --table are mutually exclusive" if json && table

        return :json if json
        return :table if table

        UNSUPPORTED_OPTIONS.each do |name|
          next unless truthy?(option(name))

          raise Errors::UsageError,
                "--#{name.to_s.tr('_', '-')} is not supported yet; use --json or --table"
        end

        from_env = env["SURE_OUTPUT"].to_s.strip.downcase
        return validate!(from_env) unless from_env.empty?

        from_profile = profile&.output.to_s.strip.downcase
        return validate!(from_profile) unless from_profile.empty?

        tty? ? :table : :json
      end

      def validate!(value)
        symbol = value.to_sym
        return symbol if FORMATS.include?(symbol)

        raise Errors::UsageError,
              "unsupported output format #{value.inspect}; use `json` or `table`"
      end

      def option(name)
        if options.respond_to?(:key?) && (options.key?(name) || options.key?(name.to_s))
          return options[name] unless options[name].nil?

          return options[name.to_s]
        end
        nil
      end

      def truthy?(value)
        value == true || value.to_s.match?(/\A(?:1|true|yes|on)\z/i)
      end
    end
  end
end

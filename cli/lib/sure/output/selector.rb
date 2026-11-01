# frozen_string_literal: true

require_relative "../errors"
require_relative "csv"
require_relative "json"
require_relative "ndjson"
require_relative "table"

module Sure
  module Output
    # Chooses one formatter for the command. Precedence is explicit flags,
    # SURE_OUTPUT, the profile's output setting, then TTY detection (D-11).
    class Selector
      FORMATS = %i[json table csv ndjson].freeze
      FLAGS = %i[json table csv ndjson].freeze

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
        when :json then Json.new(clock: clock, quiet: quiet?)
        when :table then Table.new(color: color?, quiet: quiet?)
        when :csv then Csv.new(quiet: quiet?)
        when :ndjson then Ndjson.new(quiet: quiet?)
        end
      end

      def render(result, fields: nil)
        formatter.render(result, io: stdout, stderr: stderr, fields: fields || option(:fields))
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
        selected = FLAGS.select { |name| truthy?(option(name)) }
        if selected.length > 1
          raise Errors::UsageError,
                "--#{selected.join(', --')} are mutually exclusive"
        end
        return selected.first unless selected.empty?

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
              "unsupported output format #{value.inspect}; use one of #{FORMATS.join(', ')}"
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

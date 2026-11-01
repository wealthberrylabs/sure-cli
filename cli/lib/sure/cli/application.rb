# frozen_string_literal: true

require_relative "base"
require_relative "commands/api"
require_relative "commands/auth"
require_relative "commands/completion"
require_relative "commands/doctor"

module Sure
  module CLI
    # The single Thor application. Commands stay thin: they resolve context,
    # call one service, and render one result. Only Runner renders errors.
    class Application < Base
      def self.exit_on_failure?
        false
      end

      check_unknown_options!
      map %w[--version -v] => :version

      class_option :profile, type: :string, desc: "Profile name"
      class_option :server, type: :string, desc: "Sure server URL (base URL, not /api/v1)"
      class_option :ca_bundle, type: :string, desc: "PEM CA bundle"
      class_option :insecure, type: :boolean, default: false, desc: "Disable TLS verification (dangerous)"
      class_option :json, type: :boolean, desc: "Emit a stable JSON envelope"
      class_option :table, type: :boolean, desc: "Emit a human-readable table"
      class_option :color, type: :boolean, default: true, desc: "Color output (--no-color disables)"
      class_option :quiet, type: :boolean, desc: "Suppress non-error output"
      class_option :verbose, type: :boolean, desc: "Add request IDs and timings"

      class_exclusive :json, :table
      class_exclusive :quiet, :verbose

      # Thor 1.5 builds dynamic commands with an empty options_relation, which
      # crashes when class-level exclusive groups are declared. Give unknown
      # commands the same relation keys as a normal command.
      class UnknownCommand < Thor::DynamicCommand
        def initialize(name, options = nil)
          super
          self.options_relation = { exclusive_option_names: [], at_least_one_option_names: [] }
        end
      end

      def self.dynamic_command_class
        UnknownCommand
      end

      desc "version", Sure::Catalog.fetch("version").summary
      long_desc catalog_long_desc("version")
      def version
        runtime.stdout.puts "sure #{Sure::VERSION}"
      end

      desc "help [COMMAND]", Sure::Catalog.fetch("help").summary
      long_desc catalog_long_desc("help")
      def help(*names)
        return self.class.help(shell, false) if names.empty?

        group = names.first.to_s
        if self.class.subcommands.include?(group)
          klass = self.class.subcommand_classes.fetch(group)
          names.length == 1 ? klass.help(shell, true) : klass.command_help(shell, names[1])
        elsif names.length == 1
          self.class.command_help(shell, group)
        else
          raise Thor::Error, "Could not find command \"#{group}\"."
        end
      end

      desc "auth COMMAND", "Manage stored API-key credentials"
      subcommand "auth", Commands::Auth

      desc "doctor", Sure::Catalog.fetch("doctor").summary
      long_desc catalog_long_desc("doctor")
      def doctor
        Commands::Doctor.new.call
      end

      desc "api METHOD PATH", Sure::Catalog.fetch("api").summary
      long_desc catalog_long_desc("api")
      option :data, type: :string, desc: "JSON request body"
      option :raw, type: :boolean, desc: "Print the exact response body (still redacted)"
      option :dry_run, type: :boolean, desc: "Print the request without sending it"
      option :yes, type: :boolean, desc: "Confirm a write request"
      def api(method, path)
        Commands::Api.new(runtime: runtime, options: options).call(method, path)
      end

      desc "completion SHELL", Sure::Catalog.fetch("completion").summary
      long_desc catalog_long_desc("completion")
      def completion(shell)
        Commands::Completion.new.call(shell)
      end
    end
  end
end

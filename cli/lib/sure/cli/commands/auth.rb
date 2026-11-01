# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"
require_relative "../../auth/login"
require_relative "../../auth/logout"
require_relative "../../auth/status"
require_relative "../../output/selector"

module Sure
  module CLI
    module Commands
      # Auth command group. Every subcommand resolves one service and renders
      # one Output::Result, so piped output stays valid JSON and never carries
      # the API key.
      class Auth < Sure::CLI::Base
        def self.exit_on_failure?
          false
        end

        check_unknown_options!

        class_option :profile, type: :string, desc: "Profile name"
        class_option :server, type: :string, desc: "Sure server URL (base URL, not /api/v1)"
        class_option :json, type: :boolean, desc: "Emit a stable JSON envelope"
        class_option :table, type: :boolean, desc: "Emit a human-readable table"
        class_option :csv, type: :boolean, desc: "Emit CSV"
        class_option :ndjson, type: :boolean, desc: "Emit one JSON object per line"
        class_option :fields, type: :string, desc: "Comma-separated fields to include"

        class_exclusive :json, :table, :csv, :ndjson

        desc "login", Sure::Catalog.fetch("auth.login").summary
        long_desc catalog_long_desc("auth.login")
        option :api_key_file, type: :string, desc: "Read the API key from a file"
        option :api_key_stdin, type: :boolean, desc: "Read the API key from stdin"
        def login
          render_result(Sure::Auth::Login.new(runtime: runtime, options: options).call)
        end

        desc "logout", Sure::Catalog.fetch("auth.logout").summary
        long_desc catalog_long_desc("auth.logout")
        def logout
          render_result(Sure::Auth::Logout.new(runtime: runtime, options: options).call)
        end

        desc "status", Sure::Catalog.fetch("auth.status").summary
        long_desc catalog_long_desc("auth.status")
        def status
          render_result(Sure::Auth::Status.new(context: context).call)
        end

        no_commands do
          def render_result(result)
            Output::Selector.new(
              options: options,
              env: runtime.env,
              profile: nil,
              stdout: runtime.stdout,
              stderr: runtime.stderr,
              clock: runtime.clock
            ).render(result)
          end
        end
      end
    end
  end
end

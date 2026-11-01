# frozen_string_literal: true

require_relative "../base"
require_relative "../runtime"

module Sure
  module CLI
    module Commands
      # Auth command group. Behavior arrives with the credential-store plan; the
      # command surface exists now so help and the catalog can be validated.
      class Auth < Sure::CLI::Base
        def self.exit_on_failure?
          false
        end

        check_unknown_options!

        class_option :profile, type: :string, desc: "Profile name"
        class_option :server, type: :string, desc: "Sure server URL (base URL, not /api/v1)"

        desc "login", Sure::Catalog.fetch("auth.login").summary
        long_desc catalog_long_desc("auth.login")
        option :api_key_file, type: :string, desc: "Read the API key from a file"
        option :api_key_stdin, type: :boolean, desc: "Read the API key from stdin"
        def login
          raise Sure::Errors::UsageError, NOT_IMPLEMENTED
        end

        desc "logout", Sure::Catalog.fetch("auth.logout").summary
        long_desc catalog_long_desc("auth.logout")
        def logout
          raise Sure::Errors::UsageError, NOT_IMPLEMENTED
        end

        desc "status", Sure::Catalog.fetch("auth.status").summary
        long_desc catalog_long_desc("auth.status")
        def status
          raise Sure::Errors::UsageError, NOT_IMPLEMENTED
        end
      end
    end
  end
end

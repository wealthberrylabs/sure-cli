# frozen_string_literal: true

require_relative "sure/version"
require_relative "sure/errors"
require_relative "sure/errors/mapper"
require_relative "sure/redactor"
require_relative "sure/catalog"
require_relative "sure/config"
require_relative "sure/config/resolver"
require_relative "sure/http/url_builder"
require_relative "sure/http/rate_limit"
require_relative "sure/http/pagination"
require_relative "sure/http/envelope"
require_relative "sure/http/response"
require_relative "sure/http/client"
require_relative "sure/output"
require_relative "sure/auth/store"
require_relative "sure/auth/credential"
require_relative "sure/auth/credential_key"
require_relative "sure/auth/command_runner"
require_relative "sure/auth/file_store"
require_relative "sure/auth/mac_keychain_store"
require_relative "sure/auth/secret_service_store"
require_relative "sure/auth/store_factory"
require_relative "sure/auth/api_key_provider"
require_relative "sure/auth/scope_preflight"
require_relative "sure/auth/login"
require_relative "sure/auth/logout"
require_relative "sure/auth/status"
require_relative "sure/doctor/check"
require_relative "sure/doctor/result"
require_relative "sure/doctor/runner"
require_relative "sure/completion/generator"
require_relative "sure/cli"

# Public namespace for the Sure command-line client.
module Sure
  # Only public entry point. Returns a semantic exit code; never calls exit.
  def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr,
               env: ENV, cwd: Dir.pwd, clock: Time)
    CLI::Runner.new(
      stdin: stdin, stdout: stdout, stderr: stderr,
      env: env, cwd: cwd, clock: clock
    ).call(argv)
  end
end

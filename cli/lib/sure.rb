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
require_relative "sure/auth/api_key_provider"
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

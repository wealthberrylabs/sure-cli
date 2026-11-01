# frozen_string_literal: true

require_relative "sure/version"
require_relative "sure/errors"
require_relative "sure/catalog"
require_relative "sure/config"
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

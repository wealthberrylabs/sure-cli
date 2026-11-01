# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "webmock/minitest"
require "fileutils"
require "stringio"
require "tmpdir"

require "sure"

# Helpers shared by command and unit tests.
module CLITestHelper
  FIXED_CLOCK = Time.utc(2026, 1, 1, 12, 0, 0)
  BASE_ENV = { "PATH" => ENV.fetch("PATH", "") }.freeze

  Result = Data.define(:status, :stdout, :stderr)

  # Runs the CLI against injected streams and an isolated HOME/XDG directory.
  #
  #   result = run_cli("--version")
  #   assert_equal 0, result.status
  #   assert_equal "sure 0.1.0\n", result.stdout
  def run_cli(*argv, stdin: +"", env: {})
    Dir.mktmpdir("sure-test") do |dir|
      home = File.join(dir, "home")
      config_home = File.join(dir, "config")
      FileUtils.mkdir_p([ home, config_home ])

      stdout = StringIO.new
      stderr = StringIO.new

      status = Sure.run(
        argv,
        stdin: StringIO.new(stdin),
        stdout: stdout,
        stderr: stderr,
        env: BASE_ENV.merge("HOME" => home, "XDG_CONFIG_HOME" => config_home).merge(env),
        cwd: dir,
        clock: FIXED_CLOCK
      )

      Result.new(status: status, stdout: stdout.string, stderr: stderr.string)
    end
  end
end

module Minitest
  class Test
    include CLITestHelper
  end
end

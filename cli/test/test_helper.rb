# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "webmock/minitest"
require "fileutils"
require "stringio"
require "tmpdir"

require "sure"
require "support/fake_tty"

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

  # Pass a String for a plain pipe, or a FakeTTY/FakePipe to control tty?.
  # stdout/stderr may be supplied when a command needs a TTY on those streams.
  def run_cli(*argv, stdin: +"", env: {}, stdout: nil, stderr: nil)
    Dir.mktmpdir("sure-test") do |dir|
      home = File.join(dir, "home")
      config_home = File.join(dir, "config")
      FileUtils.mkdir_p([ home, config_home ])

      stdout ||= StringIO.new
      stderr ||= StringIO.new
      stdin_io = stdin.is_a?(String) ? StringIO.new(stdin) : stdin

      status = Sure.run(
        argv,
        stdin: stdin_io,
        stdout: stdout,
        stderr: stderr,
        env: BASE_ENV.merge("HOME" => home, "XDG_CONFIG_HOME" => config_home).merge(env),
        cwd: dir,
        clock: FIXED_CLOCK
      )

      Result.new(status: status, stdout: output_of(stdout), stderr: output_of(stderr))
    end
  end

  def output_of(io)
    io.respond_to?(:string) ? io.string : io.to_s
  end

  def api_fixture(name)
    File.read(File.expand_path("fixtures/api/#{name}.json", __dir__))
  end
end

module Minitest
  class Test
    include CLITestHelper
  end
end

# frozen_string_literal: true

require "test_helper"

class CommandRunnerTest < Minitest::Test
  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.zero?
    end
  end

  def test_child_environment_keeps_only_what_a_helper_needs
    runner = Sure::Auth::CommandRunner.new(env: {
      "PATH" => "/usr/bin:/bin",
      "HOME" => "/home/tester",
      "USER" => "tester",
      "LOGNAME" => "tester",
      "TMPDIR" => "/tmp",
      "DBUS_SESSION_BUS_ADDRESS" => "unix:path=/run/user/1/bus",
      "SURE_API_KEY" => "supersecret",
      "SURE_TOKEN" => "token-value",
      "Authorization" => "Bearer token-value"
    })

    captured = capture_run(runner)

    child = captured.fetch(:environment)
    assert_equal "/usr/bin:/bin", child["PATH"]
    assert_equal "/home/tester", child["HOME"]
    assert_equal "unix:path=/run/user/1/bus", child["DBUS_SESSION_BUS_ADDRESS"]
    refute child.key?("SURE_API_KEY")
    refute child.key?("SURE_TOKEN")
    refute child.key?("Authorization")
  end

  def test_secret_is_only_passed_through_stdin
    runner = Sure::Auth::CommandRunner.new(env: { "PATH" => "/usr/bin" })

    captured = capture_run(runner, stdin_data: "the-secret")

    assert_equal "the-secret", captured.fetch(:options)[:stdin_data]
    refute_includes captured.fetch(:arguments), "the-secret"
    refute captured.fetch(:environment).value?("the-secret")
  end

  def test_missing_helper_raises_a_store_error
    runner = Sure::Auth::CommandRunner.new(env: { "PATH" => "" })

    assert_raises(Sure::Auth::StoreError) do
      runner.run("definitely-not-a-real-helper")
    end
  end

  private

  def capture_run(runner, stdin_data: nil)
    capture = {}
    Open3.stub(:capture3, lambda { |environment, command, *arguments, **options|
      capture[:environment] = environment
      capture[:command] = command
      capture[:arguments] = arguments
      capture[:options] = options
      [ "", "", Status.new(0) ]
    }) do
      result = stdin_data.nil? ? runner.run("/bin/echo", "hello") : runner.run("/bin/echo", "hello", stdin_data: stdin_data)
      assert result.success?
    end
    capture
  end
end

# frozen_string_literal: true

require "test_helper"
require "timeout"

class NonTtyTest < Minitest::Test
  SERVER = "https://sure.example.com"

  def test_auth_login_without_a_key_never_prompts_on_a_pipe
    result = timed do
      run_cli("auth", "login", "--server", SERVER, stdin: "")
    end

    assert_equal 2, result.status
    assert_includes result.stderr, "--api-key-file"
    assert_includes result.stderr, "--api-key-stdin"
    assert_includes result.stderr, "SURE_API_KEY"
    refute_includes result.stdout, "API key: "
    refute_includes result.stderr, "API key: "
  end

  def test_api_write_without_yes_never_prompts_on_a_pipe
    result = timed do
      run_cli("api", "POST", "/api/v1/tags", "--data", "{}",
              "--server", SERVER, stdin: "", env: { "SURE_API_KEY" => "test-key" })
    end

    assert_equal 2, result.status
    assert_includes result.stderr, "--yes"
    refute_includes result.stdout, "Proceed with"
    refute_includes result.stderr, "Proceed with"
  end

  def test_api_key_stdin_with_empty_input_fails_instead_of_waiting
    result = timed do
      run_cli("auth", "login", "--api-key-stdin", "--server", SERVER, stdin: "")
    end

    assert_equal 2, result.status
    assert_includes result.stderr, "empty"
    refute_includes result.stdout, "API key: "
  end

  private

  # Every path must fail fast rather than blocking on a read.
  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Timeout.timeout(2) { yield }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert elapsed < 2, "command took #{elapsed.round(2)}s with a non-TTY stdin"
    result
  end
end

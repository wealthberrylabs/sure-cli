# frozen_string_literal: true

require "test_helper"

class VersionHelpTest < Minitest::Test
  def test_version_prints_exact_version
    result = run_cli("--version")

    assert_equal 0, result.status
    assert_equal "sure 0.1.0\n", result.stdout
    assert_empty result.stderr
  end

  def test_help_lists_phase_one_command_groups
    result = run_cli("help")

    assert_equal 0, result.status
    refute_empty result.stdout
    %w[auth api doctor completion].each do |name|
      assert_includes result.stdout, name
    end
    assert_empty result.stderr
  end

  def test_help_auth_login_shows_catalog_examples
    result = run_cli("help", "auth", "login")

    assert_equal 0, result.status
    assert_includes result.stdout, "--api-key-stdin"
    assert_includes result.stdout, "sure auth login --server https://sure.example.com"
    refute_includes result.stdout, "--api-key="
  end

  def test_unknown_command_exits_two_without_backtrace
    result = run_cli("nonexistent")

    assert_equal 2, result.status
    assert_empty result.stdout
    refute_empty result.stderr
    refute_match(/backtrace|from \//, result.stderr)
  end

  def test_unknown_option_is_rejected
    result = run_cli("--version", "--bogus")

    assert_equal 2, result.status
    assert_empty result.stdout
    refute_empty result.stderr
    refute_match(/backtrace|from \//, result.stderr)
  end

  def test_doctor_reaches_its_command_class
    result = run_cli("doctor")

    assert_equal 1, result.status
    payload = JSON.parse(result.stdout)
    assert_equal "FAIL", payload.dig("data", "checks", 0, "status")
  end

  def test_completion_reaches_its_command_class
    result = run_cli("completion", "bash")

    assert_equal 2, result.status
    assert_includes result.stderr, "not implemented until its plan lands"
  end

  def test_forbidden_api_key_flag_is_rejected_without_echoing_the_secret
    result = run_cli("auth", "login", "--api-key=secret123")

    assert_equal 2, result.status
    refute_includes result.stdout, "secret123"
    refute_includes result.stderr, "secret123"
    assert_includes result.stderr, "--api-key-stdin"
    assert_includes result.stderr, "SURE_API_KEY"
  end

  def test_version_does_not_load_rails
    run_cli("--version")

    refute defined?(Rails), "the CLI must not load Rails"
    refute defined?(ActiveSupport), "the CLI must not load ActiveSupport"
  end

  def test_d13_exit_codes_are_available
    assert_equal 1, Sure::Errors::GeneralError.new("x").exit_code
    assert_equal 2, Sure::Errors::UsageError.new("x").exit_code
    assert_equal 3, Sure::Errors::AuthenticationError.new("x").exit_code
    assert_equal 3, Sure::Errors::InsufficientScopeError.new("x").exit_code
    assert_equal 4, Sure::Errors::NotFoundError.new("x").exit_code
    assert_equal 5, Sure::Errors::ValidationError.new("x").exit_code
    assert_equal 6, Sure::Errors::RateLimitedError.new("x").exit_code
    assert_equal 7, Sure::Errors::PartialFailureError.new("x").exit_code
    assert_equal 8, Sure::Errors::NetworkError.new("x").exit_code
    assert_equal 9, Sure::Errors::TimeoutError.new("x").exit_code
  end
end

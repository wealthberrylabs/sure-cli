# frozen_string_literal: true

require "test_helper"

# Thor resolves the command name from the first argv token, so the runner
# normalizes a leading run of documented global options before dispatch.
class RunnerGlobalOptionsTest < Minitest::Test
  def test_moves_a_single_leading_value_option_after_the_command
    argv = %w[--profile staging doctor]

    assert_equal %w[doctor --profile staging], normalize(argv)
  end

  def test_moves_a_leading_boolean_option_after_the_command
    argv = %w[--json doctor]

    assert_equal %w[doctor --json], normalize(argv)
  end

  def test_preserves_the_inline_value_form
    argv = %w[--profile=staging api GET /api/v1/accounts]

    assert_equal %w[api GET /api/v1/accounts --profile=staging], normalize(argv)
  end

  def test_moves_multiple_leading_options_and_keeps_relative_order
    argv = %w[--profile staging --json api GET /api/v1/accounts --verbose]

    assert_equal %w[api GET /api/v1/accounts --verbose --profile staging --json], normalize(argv)
  end

  def test_preserves_negative_boolean_flags
    argv = %w[--json --no-color api GET /api/v1/accounts]

    assert_equal %w[api GET /api/v1/accounts --json --no-color], normalize(argv)
  end

  def test_keeps_a_terminal_option_ahead_of_collected_options
    assert_equal %w[--version --json], normalize(%w[--json --version])
    assert_equal %w[--help --json], normalize(%w[--json --help])
  end

  def test_leaves_a_lone_terminal_option_unchanged
    [ %w[--version], %w[-v], %w[--help], %w[-h] ].each do |argv|
      assert_same argv, normalize(argv)
    end
  end

  def test_leaves_argv_after_a_bare_terminator_unchanged
    argv = %w[-- --json doctor]

    assert_same argv, normalize(argv)
  end

  def test_leaves_argv_without_leading_options_unchanged
    argv = %w[doctor --json]

    assert_same argv, normalize(argv)
  end

  def test_rejects_an_unknown_leading_option_without_echoing_its_value
    error = assert_raises(Sure::Errors::UsageError) do
      normalize([ "--bogus=secret123", "doctor" ])
    end

    assert_includes error.message, "--bogus"
    refute_includes error.message, "secret123"
  end

  def test_rejects_a_mistyped_leading_option
    error = assert_raises(Sure::Errors::UsageError) { normalize(%w[--jsn doctor]) }

    assert_includes error.message, "--jsn"
  end

  def test_rejects_a_value_option_without_a_value
    error = assert_raises(Sure::Errors::UsageError) { normalize(%w[--profile]) }

    assert_includes error.message, "missing value for --profile"
  end

  def test_rejects_a_value_option_followed_by_another_option
    error = assert_raises(Sure::Errors::UsageError) { normalize(%w[--profile --json doctor]) }

    assert_includes error.message, "missing value for --profile"
  end

  def test_unknown_leading_option_exits_two_without_a_help_screen
    result = run_cli("--bogus", "doctor")

    assert_equal 2, result.status
    assert_empty result.stdout
    assert_includes result.stderr, "--bogus"
  end

  def test_missing_value_exits_two_instead_of_reaching_thor
    result = run_cli("--profile")

    assert_equal 2, result.status
    assert_empty result.stdout
    assert_includes result.stderr, "--profile"
  end

  private

  def runner
    @runner ||= Sure::CLI::Runner.new(
      stdin: StringIO.new,
      stdout: StringIO.new,
      stderr: StringIO.new,
      env: {},
      cwd: Dir.pwd,
      clock: Time
    )
  end

  def normalize(argv)
    runner.send(:normalize_global_options, argv)
  end
end

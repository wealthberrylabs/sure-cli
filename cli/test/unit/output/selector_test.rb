# frozen_string_literal: true

require "test_helper"

class SelectorTest < Minitest::Test
  def test_defaults_to_json_when_stdout_is_piped
    selector = build(stdout: FakePipe.new)

    assert_equal :json, selector.format
    assert_kind_of Sure::Output::Json, selector.formatter
  end

  def test_defaults_to_table_on_a_tty
    selector = build(stdout: FakeTTY.new)

    assert_equal :table, selector.format
    assert_kind_of Sure::Output::Table, selector.formatter
  end

  def test_explicit_flags_override_tty_detection
    assert_equal :json, build(stdout: FakeTTY.new, options: { json: true }).format
    assert_equal :table, build(stdout: FakePipe.new, options: { table: true }).format
  end

  def test_rejects_json_and_table_together
    error = assert_raises(Sure::Errors::UsageError) do
      build(options: { json: true, table: true }).format
    end

    assert_includes error.message, "mutually exclusive"
  end

  def test_environment_beats_profile_and_tty
    selector = build(
      stdout: FakeTTY.new,
      env: { "SURE_OUTPUT" => "json" },
      profile: profile("table")
    )

    assert_equal :json, selector.format
  end

  def test_profile_beats_tty_detection
    selector = build(stdout: FakeTTY.new, profile: profile("json"))

    assert_equal :json, selector.format
  end

  def test_rejects_unsupported_formats
    assert_raises(Sure::Errors::UsageError) do
      build(env: { "SURE_OUTPUT" => "yaml" }).format
    end
  end

  def test_accepts_csv_and_ndjson
    assert_equal :csv, build(options: { csv: true }).format
    assert_equal :ndjson, build(options: { ndjson: true }).format
    assert_equal :csv, build(env: { "SURE_OUTPUT" => "csv" }).format
    assert_equal :ndjson, build(env: { "SURE_OUTPUT" => "ndjson" }).format
    assert_kind_of Sure::Output::Csv, build(options: { csv: true }).formatter
    assert_kind_of Sure::Output::Ndjson, build(options: { ndjson: true }).formatter
  end

  def test_rejects_multiple_output_flags
    error = assert_raises(Sure::Errors::UsageError) do
      build(options: { json: true, csv: true }).format
    end

    assert_includes error.message, "mutually exclusive"
  end

  def test_color_requires_a_tty_and_no_opt_out
    assert build(stdout: FakeTTY.new).color?
    refute build(stdout: FakePipe.new).color?
    refute build(stdout: FakeTTY.new, env: { "NO_COLOR" => "1" }).color?
    refute build(stdout: FakeTTY.new, env: { "TERM" => "dumb" }).color?
    refute build(stdout: FakeTTY.new, options: { color: false }).color?
  end

  def test_quiet_and_verbose_flags
    assert build(options: { quiet: true }).quiet?
    assert build(options: { verbose: true }).verbose?
    refute build.quiet?
    refute build.verbose?
  end

  def test_renders_through_the_selected_formatter
    stdout = FakePipe.new

    build(stdout: stdout).render(Sure::Output::Result.new(data: { "ok" => true }))

    assert_equal true, JSON.parse(stdout.string)["data"]["ok"]
  end

  private

  def build(options: {}, env: {}, profile: nil, stdout: FakePipe.new)
    Sure::Output::Selector.new(
      options: options,
      env: env,
      profile: profile,
      stdout: stdout,
      stderr: StringIO.new,
      clock: CLITestHelper::FIXED_CLOCK
    )
  end

  def profile(output)
    Sure::Config::Profile.new(name: "default", server_url: "https://sure.example.com", output: output)
  end
end

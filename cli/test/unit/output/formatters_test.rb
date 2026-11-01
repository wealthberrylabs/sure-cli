# frozen_string_literal: true

require "test_helper"

class FormattersTest < Minitest::Test
  SERVER = "https://sure.example.com"
  CLOCK = CLITestHelper::FIXED_CLOCK

  def test_csv_uses_generate_and_parses_with_the_expected_shape
    io = StringIO.new
    result = Sure::Output::Result.new(
      data: [ { "name" => "Checking", "balance" => 1250.75 } ],
      columns: [
        Sure::Output::Column.new(key: "name"),
        Sure::Output::Column.new(key: "balance")
      ]
    )

    Sure::Output::Csv.new.render(result, io: io)

    rows = CSV.parse(io.string, headers: true)
    assert_equal %w[name balance], rows.headers
    assert_equal 1, rows.length
    assert_equal "Checking", rows.first["name"]
    assert_equal "1250.75", rows.first["balance"]
  end

  def test_csv_neutralises_spreadsheet_formulas_but_preserves_numeric_negatives
    io = StringIO.new
    result = Sure::Output::Result.new(
      data: [ { "name" => "=cmd|' /C calc'!A0", "balance" => -12.34 } ],
      columns: [
        Sure::Output::Column.new(key: "name"),
        Sure::Output::Column.new(key: "balance")
      ]
    )

    Sure::Output::Csv.new.render(result, io: io)

    row = CSV.parse(io.string, headers: true).first
    assert_equal "'=cmd|' /C calc'!A0", row["name"]
    assert_equal "-12.34", row["balance"]
  end

  def test_csv_projects_fields_and_infers_a_collection
    io = StringIO.new
    result = Sure::Output::Result.new(data: JSON.parse(api_fixture("accounts")))

    Sure::Output::Csv.new.render(result, io: io, fields: "name,balance")

    rows = CSV.parse(io.string, headers: true)
    assert_equal %w[name balance], rows.headers
    assert_equal 2, rows.length
    assert_equal "Checking", rows.first["name"]
  end

  def test_ndjson_emits_one_parseable_line_per_item
    io = StringIO.new
    result = Sure::Output::Result.new(
      data: [ { "name" => "Checking" }, { "name" => "Savings" } ]
    )

    Sure::Output::Ndjson.new.render(result, io: io)

    lines = io.string.lines
    assert_equal 2, lines.length
    assert_equal %w[Checking Savings], lines.map { |line| JSON.parse(line)["name"] }
  end

  def test_ndjson_projects_fields_per_record
    io = StringIO.new
    result = Sure::Output::Result.new(
      data: [ { "name" => "Checking", "balance" => 10.0, "nested" => { "a" => 1 } } ]
    )

    Sure::Output::Ndjson.new.render(result, io: io, fields: "name,nested")

    row = JSON.parse(io.string.lines.first)
    assert_equal %w[name nested], row.keys
    assert_equal({ "a" => 1 }, row["nested"])
  end

  def test_json_projects_fields_inside_a_collection_envelope
    io = StringIO.new
    result = Sure::Output::Result.new(data: JSON.parse(api_fixture("accounts")))

    Sure::Output::Json.new(clock: CLOCK).render(result, io: io, fields: "name,balance")

    payload = JSON.parse(io.string)
    assert_equal 2, payload["data"]["accounts"].length
    assert_equal %w[name balance], payload["data"]["accounts"].first.keys
    assert payload["data"]["pagination"]
  end

  def test_table_projects_columns_and_renders_control_characters_inert
    io = StringIO.new
    result = Sure::Output::Result.new(
      data: [ { "name" => "\e[31mred\ninjected", "balance" => -12.34 } ],
      columns: [
        Sure::Output::Column.new(key: "name"),
        Sure::Output::Column.new(key: "balance")
      ]
    )

    Sure::Output::Table.new.render(result, io: io, fields: "balance")

    assert_includes io.string, "Balance"
    refute_includes io.string, "Name"
    refute_includes io.string, "\e["

    full = StringIO.new
    Sure::Output::Table.new.render(
      Sure::Output::Result.new(
        data: [ { "name" => "\e[31mred\ninjected", "balance" => -12.34 } ],
        columns: [ Sure::Output::Column.new(key: "name") ]
      ),
      io: full
    )
    refute_includes full.string, "\e["
    refute_includes full.string, "red\ninjected"
  end

  def test_unknown_field_is_a_usage_error_naming_the_field
    error = assert_raises(Sure::Errors::UsageError) do
      Sure::Output::Json.new(clock: CLOCK).render(
        Sure::Output::Result.new(data: { "name" => "Checking" }),
        io: StringIO.new,
        fields: "name,bogus"
      )
    end

    assert_includes error.message, "bogus"
  end

  def test_quiet_suppresses_warnings_but_not_data
    io = StringIO.new
    stderr = StringIO.new
    result = Sure::Output::Result.new(data: { "ok" => true }, meta: { warnings: [ "heads up" ] })

    Sure::Output::Json.new(clock: CLOCK, quiet: true).render(result, io: io, stderr: stderr)

    assert_empty stderr.string
    assert_equal true, JSON.parse(io.string).dig("data", "ok")
  end

  def test_no_format_emits_ansi_for_server_controlled_values
    data = { "name" => "\e[31mred" }
    [ Sure::Output::Json, Sure::Output::Ndjson, Sure::Output::Csv, Sure::Output::Table ].each do |klass|
      io = StringIO.new
      klass.new.render(Sure::Output::Result.new(data: [ data ]), io: io)
      refute_includes io.string, "\e[", "#{klass} leaked an ANSI sequence"
    end
  end

  def test_sure_output_csv_and_ndjson_are_accepted_at_the_command_boundary
    stub_request(:get, "#{SERVER}/api/v1/accounts")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: api_fixture("accounts"))

    csv = run_cli("api", "GET", "/api/v1/accounts", "--server", SERVER,
                  env: { "SURE_API_KEY" => "test-key", "SURE_OUTPUT" => "csv" })
    ndjson = run_cli("api", "GET", "/api/v1/accounts", "--server", SERVER,
                     env: { "SURE_API_KEY" => "test-key", "SURE_OUTPUT" => "ndjson" })

    assert_equal 0, csv.status
    assert_equal "id", CSV.parse(csv.stdout, headers: true).headers.first
    assert_equal 0, ndjson.status
    assert_equal 2, ndjson.stdout.lines.length
  end

  def test_sure_output_yaml_still_exits_two
    result = run_cli("api", "GET", "/api/v1/accounts", "--server", SERVER,
                     env: { "SURE_API_KEY" => "test-key", "SURE_OUTPUT" => "yaml" })

    assert_equal 2, result.status
    assert_includes result.stderr, "SURE_OUTPUT"
  end

  def test_fields_with_raw_exits_two
    result = run_cli("api", "GET", "/api/v1/accounts", "--raw", "--fields", "name",
                     "--server", SERVER, env: { "SURE_API_KEY" => "test-key" })

    assert_equal 2, result.status
    assert_includes result.stderr, "--fields"
    assert_not_requested :get, "#{SERVER}/api/v1/accounts"
  end

  def test_quiet_and_verbose_together_exit_two
    result = run_cli("api", "GET", "/api/v1/accounts", "--quiet", "--verbose",
                     "--server", SERVER, env: { "SURE_API_KEY" => "test-key" })

    assert_equal 2, result.status
    assert_includes result.stderr, "--quiet"
    assert_includes result.stderr, "--verbose"
  end
end

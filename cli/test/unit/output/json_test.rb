# frozen_string_literal: true

require "test_helper"

class JsonOutputTest < Minitest::Test
  def test_emits_the_stable_envelope
    io = StringIO.new
    stderr = StringIO.new

    Sure::Output::Json.new(clock: CLITestHelper::FIXED_CLOCK).render(
      Sure::Output::Result.new(data: { "status" => "ok" }),
      io: io,
      stderr: stderr
    )

    payload = JSON.parse(io.string)

    assert_equal({ "status" => "ok" }, payload["data"])
    assert_equal 1, payload["meta"]["schema_version"]
    assert_equal "2026-01-01T12:00:00Z", payload["meta"]["as_of"]
    assert_equal [], payload["meta"]["warnings"]
    assert io.string.end_with?("\n")
    assert_equal 1, io.string.count("\n")
    assert_empty stderr.string
  end

  def test_replaces_non_finite_numbers_and_appends_one_warning
    io = StringIO.new
    stderr = StringIO.new

    Sure::Output::Json.new.render(
      Sure::Output::Result.new(data: { "limit" => Float::INFINITY, "remaining" => Float::NAN }),
      io: io,
      stderr: stderr
    )

    payload = JSON.parse(io.string)

    assert_nil payload["data"]["limit"]
    assert_nil payload["data"]["remaining"]
    assert_equal 1, payload["meta"]["warnings"].length
    assert_includes stderr.string, "non-finite"
  end

  def test_includes_command_metadata_and_rate_limit
    io = StringIO.new

    Sure::Output::Json.new.render(
      Sure::Output::Result.new(
        data: [],
        meta: {
          http_status: 200,
          request_id: "req-1",
          rate_limit: Sure::HTTP::RateLimit.parse({ "X-RateLimit-Limit" => "100" }, tier: "standard"),
          pagination: Sure::HTTP::Pagination.new(page: 1, per_page: 25, total_pages: 2)
        }
      ),
      io: io
    )

    meta = JSON.parse(io.string)["meta"]

    assert_equal 200, meta["http_status"]
    assert_equal "req-1", meta["request_id"]
    assert_equal 100, meta["rate_limit"]["limit"]
    assert_equal "standard", meta["rate_limit"]["tier"]
    assert_equal 2, meta["pagination"]["next_page"]
  end

  def test_projects_fields_when_requested
    io = StringIO.new

    Sure::Output::Json.new.render(
      Sure::Output::Result.new(data: [ { "name" => "Checking", "balance" => 1.0, "id" => "x" } ]),
      io: io,
      fields: %w[name balance]
    )

    assert_equal({ "name" => "Checking", "balance" => 1.0 }, JSON.parse(io.string)["data"].first)
  end
end

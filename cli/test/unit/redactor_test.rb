# frozen_string_literal: true

require "test_helper"

class RedactorTest < Minitest::Test
  def test_masks_the_active_secret_in_free_text
    redactor = Sure::Redactor.new(active_secret: "tok_live_abc123")

    redacted = redactor.redact_value("server said tok_live_abc123 was rejected")

    assert_includes redacted, "[REDACTED]"
    refute_includes redacted, "tok_live_abc123"
  end

  def test_masks_sensitive_headers
    redactor = Sure::Redactor.new

    headers = redactor.redact_headers(
      "Authorization" => "Bearer abc",
      "X-Api-Key" => "abc",
      "Content-Type" => "application/json"
    )

    assert_equal "[REDACTED]", headers["Authorization"]
    assert_equal "[REDACTED]", headers["X-Api-Key"]
    assert_equal "application/json", headers["Content-Type"]
  end

  def test_masks_header_and_query_assignments
    redactor = Sure::Redactor.new

    assert_equal "X-Api-Key: [REDACTED]", redactor.redact_value("X-Api-Key: abc")
    assert_equal "Authorization: [REDACTED]", redactor.redact_value("Authorization: Bearer abc")
    assert_equal "GET /x?api_key=[REDACTED]", redactor.redact_value("GET /x?api_key=abc")
  end

  def test_masks_json_style_keys
    redactor = Sure::Redactor.new

    redacted = redactor.redact_value('{"api_key":"abc","access_token":"def","name":"ok"}')

    refute_includes redacted, "abc"
    refute_includes redacted, "def"
    assert_includes redacted, '"name":"ok"'
    assert_equal 2, redacted.scan("[REDACTED]").length
  end

  def test_masks_64_hex_key_shapes
    redactor = Sure::Redactor.new
    key = "a" * 64

    refute_includes redactor.redact_value("key #{key}"), key
  end

  def test_scrub_env_drops_secret_variables
    redactor = Sure::Redactor.new

    scrubbed = redactor.scrub_env(
      "PATH" => "/usr/bin",
      "HOME" => "/home/ada",
      "SURE_API_KEY" => "abc",
      "SURE_ACCESS_TOKEN" => "def",
      "GITHUB_TOKEN" => "ghi"
    )

    assert_equal({ "PATH" => "/usr/bin", "HOME" => "/home/ada" }, scrubbed)
  end

  def test_leaves_ordinary_text_untouched
    redactor = Sure::Redactor.new(active_secret: "tok_live_abc123")

    assert_equal "the accounts page has 2 rows", redactor.redact_value("the accounts page has 2 rows")
  end

  def test_inspect_never_reveals_the_secret
    redactor = Sure::Redactor.new(active_secret: "tok_live_abc123")

    refute_includes redactor.inspect, "tok_live_abc123"
    assert_includes redactor.inspect, "[REDACTED]"
  end
end

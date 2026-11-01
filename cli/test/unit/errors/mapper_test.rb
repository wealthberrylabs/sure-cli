# frozen_string_literal: true

require "test_helper"

class MapperTest < Minitest::Test
  def test_maps_authentication_statuses_to_exit_three
    [ 401, 403 ].each do |status|
      error = map_status(status, { "message" => "nope" })

      assert_kind_of Sure::Errors::AuthenticationError, error
      assert_equal 3, error.exit_code
      assert_equal status, error.http_status
    end
  end

  def test_maps_not_found_to_exit_four
    error = map_status(404, { "message" => "missing" })

    assert_kind_of Sure::Errors::NotFoundError, error
    assert_equal 4, error.exit_code
  end

  def test_maps_validation_statuses_to_exit_five
    [ 400, 409, 422 ].each do |status|
      error = map_status(status, { "message" => "bad", "errors" => [ "name can't be blank" ] })

      assert_kind_of Sure::Errors::ValidationError, error
      assert_equal 5, error.exit_code
      assert_equal({ "errors" => [ "name can't be blank" ] }, error.details)
    end
  end

  def test_maps_rate_limit_to_exit_six
    error = map_status(429, { "message" => "slow down" }, headers: { "Retry-After" => "120" })

    assert_kind_of Sure::Errors::RateLimitedError, error
    assert_equal 6, error.exit_code
    assert_includes error.message, "slow down"
  end

  def test_maps_timeout_statuses_to_exit_nine
    [ 408, 504 ].each do |status|
      error = map_status(status, { "message" => "timeout" })

      assert_kind_of Sure::Errors::TimeoutError, error
      assert_equal 9, error.exit_code
    end
  end

  def test_maps_server_errors_to_exit_eight_without_echoing_the_body
    error = map_status(500, { "message" => "secret detail abc" })

    assert_kind_of Sure::Errors::NetworkError, error
    assert_equal 8, error.exit_code
    refute_includes error.message, "secret detail abc"
  end

  def test_maps_redirects_to_exit_eight
    error = map_status(302, nil, headers: { "Location" => "https://evil.example" })

    assert_kind_of Sure::Errors::NetworkError, error
    assert_equal 8, error.exit_code
    assert_includes error.message, "redirect"
  end

  def test_preserves_response_metadata_for_doctor
    error = map_status(
      401,
      JSON.parse(api_fixture("error_401")),
      headers: { "Date" => "Sat, 31 Oct 2026 12:00:00 GMT", "X-Request-Id" => "req-123" }
    )

    assert_equal 401, error.http_status
    assert_equal "Sat, 31 Oct 2026 12:00:00 GMT", error.headers["Date"]
    assert_equal "req-123", error.request_id
  end

  def test_maps_timeout_exceptions_to_exit_nine
    assert_equal 9, Sure::Errors::Mapper.map(Faraday::TimeoutError.new("timed out")).exit_code
    assert_equal 9, Sure::Errors::Mapper.map(Timeout::Error.new("timed out")).exit_code
  end

  def test_maps_connection_failures_to_exit_eight
    assert_equal 8, Sure::Errors::Mapper.map(Faraday::ConnectionFailed.new("refused")).exit_code
  end

  def test_maps_thor_errors_to_usage
    error = Sure::Errors::Mapper.map(Thor::Error.new("Unknown command"))

    assert_kind_of Sure::Errors::UsageError, error
    assert_equal 2, error.exit_code
  end

  def test_redacts_credentials_from_a_synthetic_faraday_exception
    response = {
      status: 401,
      headers: { "Content-Type" => "application/json" },
      body: { "error" => "unauthorized", "message" => "header X-Api-Key: abc was rejected" }
    }
    error = Faraday::UnauthorizedError.new("the server responded with status 401", response)

    mapped = Sure::Errors::Mapper.map(error, redactor: Sure::Redactor.new)

    assert_includes mapped.message, "[REDACTED]"
    refute_includes mapped.message, "abc"
  end

  def test_does_not_echo_a_faraday_exception_message_that_contains_headers
    exception = Faraday::ConnectionFailed.new("X-Api-Key: abc could not connect")

    mapped = Sure::Errors::Mapper.map(exception, redactor: Sure::Redactor.new(active_secret: "tok_live_abc123"))

    refute_includes mapped.message, "abc"
  end

  def test_maps_malformed_json_to_network_error
    error = Sure::Errors::Mapper.map(JSON::ParserError.new("unexpected token"))

    assert_kind_of Sure::Errors::NetworkError, error
    assert_equal 8, error.exit_code
  end

  def test_returns_already_typed_errors_unchanged
    original = Sure::Errors::UsageError.new("bad input")

    assert_same original, Sure::Errors::Mapper.map(original)
  end

  def test_runner_writes_structured_json_errors_in_machine_mode
    result = run_cli("api", "TRACE", "/api/v1/accounts")

    payload = JSON.parse(result.stderr)

    assert_equal "usage_error", payload["error"]
    %w[error message details request_id http_status exit_code].each do |key|
      assert payload.key?(key), "expected #{key.inspect} in the error envelope"
    end
    assert_equal 2, payload["exit_code"]
    refute_match(/\.rb:\d+/, result.stderr)
  end

  def test_runner_writes_one_human_line_on_a_tty
    result = run_cli("api", "TRACE", "/api/v1/accounts", stdout: FakeTTY.new)

    assert_equal 2, result.status
    assert_match(/\Aerror: /, result.stderr)
    refute result.stderr.start_with?("{")
  end

  def test_runner_redacts_the_environment_key_from_errors
    result = run_cli("api", "TRACE", "/api/v1/accounts", env: { "SURE_API_KEY" => "tok_live_abc123" })

    refute_includes result.stderr, "tok_live_abc123"
  end

  def test_runner_redacts_a_key_shaped_token_from_thor_errors
    result = run_cli("auth", "nonexistent", env: { "SURE_API_KEY" => "tok_live_abc123" })

    assert_equal 2, result.status
    refute_includes result.stderr, "tok_live_abc123"
  end

  private

  def map_status(status, body, headers: {})
    Sure::Errors::Mapper.map_response(
      status: status,
      body: body,
      headers: headers,
      redactor: Sure::Redactor.new
    )
  end
end

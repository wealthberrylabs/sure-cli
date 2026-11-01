# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  SERVER = "https://sure.example.com"
  ACCOUNTS_URL = "#{SERVER}/api/v1/accounts"

  def test_sends_exactly_one_api_key_header_and_no_authorization
    stub_request(:get, ACCOUNTS_URL)
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))

    response = build_client.get("/api/v1/accounts")

    assert_equal 200, response.status
    assert_equal "Checking", response.body["accounts"].first["name"]
    assert_requested(:get, ACCOUNTS_URL) do |request|
      request.headers["X-Api-Key"] == "test-key" &&
        !request.headers.key?("Authorization")
    end
  end

  def test_provider_is_resolved_once_per_connection
    stub_request(:get, ACCOUNTS_URL)
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))
    client = build_client

    2.times { client.get("/api/v1/accounts") }

    assert_equal 1, client.instance_variable_get(:@auth_provider).calls
  end

  def test_preserves_the_server_path_prefix
    url = "#{SERVER}/sure/api/v1/accounts"
    stub_request(:get, url)
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))

    build_client(server: "#{SERVER}/sure").get("/api/v1/accounts")

    assert_requested(:get, url)
  end

  def test_captures_response_metadata
    stub_request(:get, ACCOUNTS_URL)
      .to_return(
        status: 200,
        headers: json_headers.merge(
          "X-Request-Id" => "req-42",
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "96",
          "X-RateLimit-Reset" => "2314"
        ),
        body: api_fixture("accounts")
      )

    response = build_client.get("/api/v1/accounts")

    assert_equal "req-42", response.request_id
    assert_equal 100, response.rate_limit.limit
    assert_equal 96, response.rate_limit.remaining
    assert_equal 2314, response.rate_limit.reset_in_seconds
    assert_includes response.raw_body, "\"accounts\""
    assert_operator response.duration, :>=, 0
  end

  def test_maps_http_failures_to_semantic_errors
    {
      401 => [ Sure::Errors::AuthenticationError, 3 ],
      404 => [ Sure::Errors::NotFoundError, 4 ],
      422 => [ Sure::Errors::ValidationError, 5 ],
      429 => [ Sure::Errors::RateLimitedError, 6 ],
      500 => [ Sure::Errors::NetworkError, 8 ]
    }.each do |status, (klass, exit_code)|
      stub_request(:post, "#{SERVER}/api/v1/tags")
        .to_return(status: status, headers: json_headers, body: api_fixture(error_fixture(status)))

      error = assert_raises(klass) { build_client.request("POST", "/api/v1/tags", body: {}) }

      assert_equal exit_code, error.exit_code
      assert_equal status, error.http_status
    end
  end

  def test_authentication_failure_keeps_headers_for_doctor
    stub_request(:get, ACCOUNTS_URL)
      .to_return(
        status: 401,
        headers: json_headers.merge("Date" => "Sat, 31 Oct 2026 12:00:00 GMT"),
        body: api_fixture("error_401")
      )

    error = assert_raises(Sure::Errors::AuthenticationError) do
      build_client.get("/api/v1/accounts")
    end

    assert_equal 401, error.http_status
    assert_equal "Sat, 31 Oct 2026 12:00:00 GMT", error.headers["Date"]
  end

  def test_retries_a_get_at_most_twice
    stub_request(:get, ACCOUNTS_URL).to_return(
      { status: 503, headers: json_headers, body: "" },
      { status: 503, headers: json_headers, body: "" },
      { status: 200, headers: json_headers, body: api_fixture("accounts") }
    )

    response = build_client.get("/api/v1/accounts")

    assert_equal 200, response.status
    assert_requested :get, ACCOUNTS_URL, times: 3
  end

  def test_never_retries_a_write
    stub_request(:post, "#{SERVER}/api/v1/tags")
      .to_return(status: 503, headers: json_headers, body: "")

    assert_raises(Sure::Errors::NetworkError) do
      build_client.request("POST", "/api/v1/tags", body: { tag: { name: "trip" } })
    end

    assert_requested :post, "#{SERVER}/api/v1/tags", times: 1
  end

  def test_does_not_follow_redirects
    stub_request(:get, ACCOUNTS_URL)
      .to_return(status: 302, headers: { "Location" => "https://evil.example/steal" }, body: "")

    assert_raises(Sure::Errors::NetworkError) { build_client.get("/api/v1/accounts") }

    assert_requested :get, ACCOUNTS_URL, times: 1
    assert_not_requested :get, "https://evil.example/steal"
  end

  def test_maps_timeouts_to_exit_nine
    stub_request(:post, "#{SERVER}/api/v1/tags").to_timeout

    error = assert_raises(Sure::Errors::TimeoutError) do
      build_client.request("POST", "/api/v1/tags", body: {})
    end

    assert_equal 9, error.exit_code
  end

  def test_verbose_logging_contains_no_headers_or_key
    stub_request(:get, ACCOUNTS_URL)
      .to_return(status: 200, headers: json_headers.merge("X-Request-Id" => "req-9"), body: api_fixture("accounts"))
    stderr = StringIO.new

    build_client(verbose: true, stderr: stderr).get("/api/v1/accounts")

    assert_includes stderr.string, "GET /api/v1/accounts 200"
    assert_includes stderr.string, "request_id=req-9"
    refute_includes stderr.string, "test-key"
    refute_includes stderr.string, "X-Api-Key"
    refute_includes stderr.string, "Checking"
  end

  def test_redacts_server_messages_with_the_active_secret
    stub_request(:post, "#{SERVER}/api/v1/tags")
      .to_return(
        status: 422,
        headers: json_headers,
        body: JSON.generate({ "error" => "validation_failed", "message" => "key tok_live_abc123 is invalid" })
      )

    error = assert_raises(Sure::Errors::ValidationError) do
      build_client(secret: "tok_live_abc123").request("POST", "/api/v1/tags", body: {})
    end

    refute_includes error.message, "tok_live_abc123"
    assert_includes error.message, "[REDACTED]"
  end

  def test_empty_body_is_a_success
    stub_request(:delete, "#{SERVER}/api/v1/accounts/1")
      .to_return(status: 204, headers: {}, body: "")

    response = build_client.request("DELETE", "/api/v1/accounts/1")

    assert response.success?
    assert response.empty?
    assert_equal "", response.body.to_s
  end

  def test_rate_limit_parser_tolerates_missing_and_infinite_values
    assert_equal 120, Sure::HTTP::RateLimit.parse({ "X-RateLimit-Reset" => "120" }).reset_in_seconds
    assert_nil Sure::HTTP::RateLimit.parse({ "X-RateLimit-Reset" => "" }).reset_in_seconds
    assert_nil Sure::HTTP::RateLimit.parse({ "X-RateLimit-Reset" => "Infinity" }).reset_in_seconds
    assert_nil Sure::HTTP::RateLimit.parse({}).limit
    assert Sure::HTTP::RateLimit.parse({ "X-RateLimit-Limit" => "Infinity" }).unlimited?
    assert Sure::HTTP::RateLimit.parse({}, tier: "noop").unlimited?
  end

  def test_raise_error_does_not_attach_request_headers_to_exceptions
    stub_request(:get, ACCOUNTS_URL)
      .to_return(status: 401, headers: json_headers, body: api_fixture("error_401"))
    connection = Sure::HTTP::Connection.build(
      profile: Sure::Config::Profile.new(name: "default", server_url: SERVER),
      auth_provider: CountingProvider.new("test-key")
    )

    error = assert_raises(Faraday::UnauthorizedError) { connection.get(ACCOUNTS_URL) }

    refute error.response.key?(:request)
  end

  private

  def build_client(server: SERVER, secret: "test-key", verbose: false, stderr: nil)
    profile = Sure::Config::Profile.new(name: "default", server_url: server)
    runtime = Sure::CLI::Runtime.new(
      stdin: StringIO.new,
      stdout: StringIO.new,
      stderr: stderr || StringIO.new,
      env: {},
      cwd: Dir.pwd,
      clock: Time
    )

    Sure::HTTP::Client.new(
      profile: profile,
      auth_provider: CountingProvider.new(secret),
      url_builder: Sure::HTTP::UrlBuilder.new(server),
      runtime: runtime,
      verbose: verbose
    )
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end

  def error_fixture(status)
    case status
    when 401 then "error_401"
    when 429 then "error_429"
    when 500 then "error_500"
    else "error_500"
    end
  end

  class CountingProvider
    attr_reader :calls

    def initialize(secret)
      @secret = secret
      @calls = 0
    end

    def fetch(_profile)
      @calls += 1
      [ @secret, :environment ]
    end
  end
end

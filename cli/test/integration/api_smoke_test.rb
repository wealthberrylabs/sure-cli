# frozen_string_literal: true

require "test_helper"
require "support/local_http_server"

# End-to-end proof for Phase 1: argv -> Thor -> Context -> Faraday -> output,
# against a real local TCP server (never a live Sure instance).
class ApiSmokeTest < Minitest::Test
  def setup
    WebMock.allow_net_connect!
  end

  def teardown
    @server&.stop
    WebMock.disable_net_connect!
  end

  def test_get_accounts_returns_the_envelope_and_one_api_key_header
    @server = LocalHttpServer.new(
      responses: [
        { status: 200, headers: json_headers, body: api_fixture("accounts") }
      ]
    )

    result = run_cli(
      "api", "GET", "/api/v1/accounts",
      "--server", @server.url,
      "--json",
      env: { "SURE_API_KEY" => "test-key" }
    )

    assert_equal 0, result.status, result.stderr
    payload = JSON.parse(result.stdout)
    assert_equal 2, payload["data"]["accounts"].length
    assert_equal 1, payload["meta"]["schema_version"]
    refute_includes result.stdout, "test-key"
    refute_includes result.stderr, "test-key"

    requests = @server.received
    assert_equal 1, requests.length
    request = requests.first
    assert_equal "GET", request.method
    assert_equal "/api/v1/accounts", request.path
    assert_equal "test-key", request.headers["x-api-key"]
    refute request.headers.key?("authorization")
  end

  def test_preserves_the_server_path_prefix
    @server = LocalHttpServer.new(
      responses: [
        { status: 200, headers: json_headers, body: api_fixture("accounts") }
      ]
    )

    result = run_cli(
      "api", "GET", "/api/v1/accounts",
      "--server", "#{@server.url}/sure",
      env: { "SURE_API_KEY" => "test-key" }
    )

    assert_equal 0, result.status, result.stderr
    assert_equal "/sure/api/v1/accounts", @server.received.first.path
  end

  def test_maps_a_401_to_exit_three_without_printing_the_key
    @server = LocalHttpServer.new(
      responses: [
        { status: 401, headers: json_headers, body: api_fixture("error_401") }
      ]
    )

    result = run_cli(
      "api", "GET", "/api/v1/accounts",
      "--server", @server.url,
      env: { "SURE_API_KEY" => "test-key" }
    )

    assert_equal 3, result.status
    payload = JSON.parse(result.stderr)
    assert_equal "authentication_error", payload["error"]
    assert_equal 401, payload["http_status"]
    assert_equal 3, payload["exit_code"]
    refute_includes result.stdout, "test-key"
    refute_includes result.stderr, "test-key"
  end

  private

  def json_headers
    { "Content-Type" => "application/json" }
  end
end

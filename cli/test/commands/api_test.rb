# frozen_string_literal: true

require "test_helper"

class ApiCommandTest < Minitest::Test
  SERVER = "https://sure.example.com"
  ENV_KEY = { "SURE_API_KEY" => "test-key" }.freeze

  def test_get_prints_the_documented_envelope
    stub_request(:get, "#{SERVER}/api/v1/accounts")
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))

    result = run_cli("api", "GET", "/api/v1/accounts", "--server", SERVER, "--json", env: ENV_KEY)

    assert_equal 0, result.status
    payload = JSON.parse(result.stdout)
    assert_equal 2, payload["data"]["accounts"].length
    assert_equal 1, payload["meta"]["schema_version"]
    assert_equal 200, payload["meta"]["http_status"]
    assert_includes result.stdout, "Checking"
    assert_empty result.stderr
  end

  def test_renders_a_table_on_a_tty
    stub_request(:get, "#{SERVER}/api/v1/accounts")
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))

    result = run_cli("api", "GET", "/api/v1/accounts", "--server", SERVER,
                     env: ENV_KEY, stdout: FakeTTY.new)

    assert_equal 0, result.status
    assert_includes result.stdout, "Checking"
    refute result.stdout.start_with?("{")
  end

  def test_rejects_absolute_urls_without_making_a_request
    result = run_cli("api", "GET", "http://evil.example/api/v1/accounts", "--server", SERVER, env: ENV_KEY)

    assert_equal 2, result.status
    assert_no_requests
  end

  def test_rejects_paths_outside_api_v1
    [
      "/api/v10/accounts",
      "/v1/accounts",
      "/up",
      "/api/v1/../../admin",
      "/api/v1/%2e%2e/admin",
      "/api/v1/accounts%2fadmin"
    ].each do |path|
      result = run_cli("api", "GET", path, "--server", SERVER, env: ENV_KEY)

      assert_equal 2, result.status, "expected #{path.inspect} to be rejected"
    end
    assert_no_requests
  end

  def test_accepts_the_api_root_and_a_query_string
    stub_request(:get, "#{SERVER}/api/v1").to_return(status: 200, headers: json_headers, body: "{}")
    stub_request(:get, "#{SERVER}/api/v1/accounts?per_page=1")
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))

    root = run_cli("api", "GET", "/api/v1", "--server", SERVER, env: ENV_KEY)
    query = run_cli("api", "GET", "/api/v1/accounts?per_page=1", "--server", SERVER, env: ENV_KEY)

    assert_equal 0, root.status
    assert_equal 0, query.status
    assert_requested :get, "#{SERVER}/api/v1"
    assert_requested :get, "#{SERVER}/api/v1/accounts?per_page=1"
  end

  def test_rejects_data_on_get
    result = run_cli("api", "GET", "/api/v1/accounts", "--data", "{}", "--server", SERVER, env: ENV_KEY)

    assert_equal 2, result.status
    assert_includes result.stderr, "--data"
    assert_no_requests
  end

  def test_rejects_raw_with_json
    result = run_cli("api", "GET", "/api/v1/accounts", "--raw", "--json", "--server", SERVER, env: ENV_KEY)

    assert_equal 2, result.status
    assert_no_requests
  end

  def test_refuses_a_write_without_yes_on_a_pipe
    result = run_cli("api", "DELETE", "/api/v1/accounts/1", "--server", SERVER, env: ENV_KEY)

    assert_equal 2, result.status
    assert_includes result.stderr, "--yes"
    assert_no_requests
  end

  def test_prompts_for_a_write_on_a_tty_and_aborts_on_n
    stdin = FakeTTY.new("n\n")

    result = run_cli("api", "DELETE", "/api/v1/accounts/1", "--server", SERVER,
                     env: ENV_KEY, stdin: stdin, stdout: FakeTTY.new)

    assert_equal 2, result.status
    assert_includes result.stderr, "Proceed with DELETE /api/v1/accounts/1? [y/N]"
    assert_no_requests
  end

  def test_prompts_for_a_write_on_a_tty_and_sends_on_y
    stub_usage_scopes("read_write")
    stub_request(:delete, "#{SERVER}/api/v1/accounts/1")
      .to_return(status: 204, headers: {}, body: "")
    stdin = FakeTTY.new("y\n")

    result = run_cli("api", "DELETE", "/api/v1/accounts/1", "--server", SERVER,
                     env: ENV_KEY, stdin: stdin, stdout: FakeTTY.new)

    assert_equal 0, result.status
    assert_includes result.stderr, "Proceed with DELETE"
    assert_requested :delete, "#{SERVER}/api/v1/accounts/1"
  end

  def test_yes_sends_a_write_without_prompting
    stub_usage_scopes("read_write")
    stub_request(:post, "#{SERVER}/api/v1/tags")
      .to_return(status: 201, headers: json_headers, body: '{"tag":{"id":1}}')

    result = run_cli("api", "POST", "/api/v1/tags", "--data", '{"tag":{"name":"trip"}}',
                     "--yes", "--server", SERVER, env: ENV_KEY)

    assert_equal 0, result.status
    assert_requested(:post, "#{SERVER}/api/v1/tags") do |request|
      JSON.parse(request.body) == { "tag" => { "name" => "trip" } }
    end
  end

  def test_a_read_only_environment_key_blocks_a_write_before_the_target_request
    stub_usage_scopes("read")

    result = run_cli("api", "POST", "/api/v1/tags", "--data", "{}", "--yes",
                     "--server", SERVER, env: ENV_KEY)

    assert_equal 3, result.status
    assert_includes result.stderr, "read_write"
    assert_not_requested :post, "#{SERVER}/api/v1/tags"
  end

  def test_dry_run_makes_no_request_and_reads_no_credential
    result = run_cli("api", "--dry-run", "POST", "/api/v1/tags",
                     "--data", '{"tag":{"name":"trip"}}',
                     "--server", SERVER, env: {})

    assert_equal 0, result.status
    assert_includes result.stdout, "POST #{SERVER}/api/v1/tags"
    assert_includes result.stdout, '"name": "trip"'
    refute_includes result.stdout, "test-key"
    assert_no_requests
  end

  def test_raw_output_is_still_redacted
    stub_request(:get, "#{SERVER}/api/v1/accounts")
      .to_return(status: 200, headers: json_headers, body: '{"note":"tok_live_abc123"}')

    result = run_cli("api", "GET", "/api/v1/accounts", "--raw", "--server", SERVER,
                     env: { "SURE_API_KEY" => "tok_live_abc123" })

    assert_equal 0, result.status
    assert_includes result.stdout, "[REDACTED]"
    refute_includes result.stdout, "tok_live_abc123"
  end

  def test_preserves_the_server_path_prefix
    stub_request(:get, "#{SERVER}/sure/api/v1/accounts")
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))

    result = run_cli("api", "GET", "/api/v1/accounts", "--server", "#{SERVER}/sure", env: ENV_KEY)

    assert_equal 0, result.status
    assert_requested :get, "#{SERVER}/sure/api/v1/accounts"
  end

  def test_verbose_writes_no_secret_to_stderr
    stub_request(:get, "#{SERVER}/api/v1/accounts")
      .to_return(status: 200, headers: json_headers.merge("X-Request-Id" => "req-7"),
                 body: api_fixture("accounts"))

    result = run_cli("api", "GET", "/api/v1/accounts", "--verbose", "--server", SERVER, env: ENV_KEY)

    assert_equal 0, result.status
    assert_includes result.stderr, "GET /api/v1/accounts 200"
    assert_includes result.stderr, "request_id=req-7"
    refute_includes result.stderr, "test-key"
    refute_includes result.stderr, "X-Api-Key"
  end

  def test_context_builds_one_memoized_client_and_resolves_the_provider_once
    runtime = Sure::CLI::Runtime.new(
      stdin: StringIO.new,
      stdout: StringIO.new,
      stderr: StringIO.new,
      env: { "SURE_API_KEY" => "test-key" },
      cwd: Dir.pwd,
      clock: Time
    )
    context = Sure::CLI::Context.new(runtime: runtime, options: { server: SERVER })

    calls = 0
    provider = context.auth_provider
    provider.define_singleton_method(:fetch) do |_profile|
      calls += 1
      [ "test-key", :environment ]
    end

    client = context.client
    assert_same client, context.client
    assert_same provider, context.auth_provider
    assert_same context.redactor, client.redactor

    stub_request(:get, "#{SERVER}/api/v1/accounts")
      .to_return(status: 200, headers: json_headers, body: api_fixture("accounts"))
    2.times { client.get("/api/v1/accounts") }

    assert_equal 1, calls
  end

  private

  def stub_usage_scopes(scope)
    stub_request(:get, "#{SERVER}/api/v1/usage")
      .to_return(status: 200, headers: json_headers,
                 body: JSON.generate({ "api_key" => { "scopes" => [ scope ] } }))
  end

  def json_headers
    { "Content-Type" => "application/json" }
  end

  def assert_no_requests
    assert_equal 0, WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
  end
end

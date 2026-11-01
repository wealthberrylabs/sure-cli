# frozen_string_literal: true

require "test_helper"
require "support/local_http_server"
require_relative "../support/temp_config"

class DoctorCommandTest < Minitest::Test
  include TempConfig

  SECRET = "sk_doctor_secret"

  def setup
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  def teardown
    WebMock.disable_net_connect!
  end

  def test_without_a_config_file_reports_check_one_and_exits_one
    result = run_cli("doctor", "--json")

    assert_equal 1, result.status
    checks = JSON.parse(result.stdout).dig("data", "checks")
    config = checks.find { |check| check["id"] == "config" }
    assert_equal "FAIL", config["status"]
    assert_includes config["fix"], "sure auth login"
    assert_equal %w[id label status detail fix], config.keys
  end

  def test_a_healthy_login_passes_and_prints_the_full_checklist_as_json
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [
        response(usage_body(scopes: [ "read_write" ]), headers: date_headers),
        response(usage_body(scopes: [ "read_write" ]), headers: date_headers),
        response(api_fixture("accounts"))
      ])

      login = run_cli("auth", "login", "--api-key-stdin", "--server", server.url,
                      stdin: SECRET, env: env)
      assert_equal 0, login.status

      result = run_cli("doctor", "--json", env: env)

      assert_equal 0, result.status
      checks = JSON.parse(result.stdout).dig("data", "checks")
      assert_equal 9, checks.length
      assert checks.all? { |check| %w[PASS WARN].include?(check["status"]) }
      assert_equal 3, server.received.length
      assert_equal [ "/api/v1/usage", "/api/v1/accounts?per_page=1" ],
                   server.received.last(2).map(&:path)
    ensure
      server&.stop
    end
  end

  def test_human_output_uses_ascii_labels_for_every_status_and_no_ansi
    with_temp_config_home do |env|
      paths = paths_for(env)
      server = LocalHttpServer.new(responses: [
        { status: 401, headers: json_headers(date: CLITestHelper::FIXED_CLOCK.httpdate), body: "{}" }
      ])
      write_config(paths, config_for(server.url))
      write_credential(env, server.url, SECRET)

      result = run_cli("doctor", env: env, stdout: FakeTTY.new)

      assert_equal 3, result.status
      %w[PASS WARN FAIL SKIP].each { |label| assert_includes result.stdout, label }
      refute_includes result.stdout, "\e["
    ensure
      server&.stop
    end
  end

  private

  def response(body, status: 200, headers: {})
    { status: status, headers: json_headers.merge(headers), body: body }
  end

  def date_headers
    { "Date" => CLITestHelper::FIXED_CLOCK.httpdate }
  end

  def json_headers(date: nil)
    headers = { "Content-Type" => "application/json" }
    headers["Date"] = date if date
    headers
  end

  def usage_body(scopes: [ "read" ])
    JSON.generate({
      "user" => { "email" => "user@example.com", "first_name" => "Ada", "last_name" => "Lovelace" },
      "api_key" => { "name" => "doctor key", "scopes" => scopes },
      "rate_limit" => { "tier" => "standard", "limit" => 100, "remaining" => 99 }
    })
  end

  def config_for(server_url)
    {
      "schema_version" => 1,
      "default_profile" => "default",
      "profiles" => { "default" => { "server_url" => server_url, "credential_store" => "file" } }
    }
  end

  def write_credential(env, server_url, secret)
    paths = Sure::Config::Paths.new(env: env)
    store = Sure::Auth::FileStore.new(paths: paths)
    key = Sure::Auth::CredentialKey.new(profile: "default", origin: server_url)
    store.write(key, Sure::Auth::Credential.new(
                       kind: :api_key,
                       secret: secret,
                       server_url: server_url,
                       created_at: CLITestHelper::FIXED_CLOCK
                     ))
  end
end

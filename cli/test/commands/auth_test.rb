# frozen_string_literal: true

require "test_helper"
require "support/local_http_server"
require_relative "../support/temp_config"

class AuthCommandTest < Minitest::Test
  include TempConfig

  SECRET = "sk_command_secret"

  def setup
    WebMock.allow_net_connect!
  end

  def teardown
    WebMock.disable_net_connect!
  end

  def test_login_from_stdin_writes_the_profile_and_a_private_credential
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      result = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url, "--json",
        stdin: SECRET, env: env
      )

      assert_equal 0, result.status
      payload = JSON.parse(result.stdout)
      assert_equal "default", payload.dig("data", "profile")
      assert_equal "file", payload.dig("data", "credential_source")
      assert_equal [ "read" ], payload.dig("data", "scopes")
      refute_includes result.stdout, SECRET
      refute_includes result.stderr, SECRET

      config = YAML.safe_load_file(File.join(xdg, "sure", "config.yml"))
      assert_equal server.url, config.dig("profiles", "default", "server_url")
      assert_equal "file", config.dig("profiles", "default", "credential_store")

      credentials_path = File.join(xdg, "sure", "credentials.json")
      assert_equal 0o600, File.stat(credentials_path).mode & 0o777
      credentials = JSON.parse(File.read(credentials_path))
      assert_equal 1, credentials["credentials"].length
    ensure
      server&.stop
    end
  end

  def test_a_rejected_key_exits_three_without_writing_anything
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [
        response('{"error":"unauthorized","message":"bad key"}', status: 401)
      ])

      result = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url,
        stdin: SECRET, env: env
      )

      assert_equal 3, result.status
      refute File.exist?(File.join(xdg, "sure", "credentials.json"))
      refute File.exist?(File.join(xdg, "sure", "config.yml"))
    ensure
      server&.stop
    end
  end

  def test_both_input_flags_exit_two
    with_temp_config_home do |env, _home, _xdg|
      result = run_cli(
        "auth", "login", "--api-key-file", "key.txt", "--api-key-stdin",
        "--server", "https://sure.example.com", env: env
      )

      assert_equal 2, result.status
      assert_includes result.stderr, "mutually exclusive"
    end
  end

  def test_non_tty_without_a_key_exits_two_with_flag_guidance
    with_temp_config_home do |env, _home, _xdg|
      result = run_cli(
        "auth", "login", "--server", "https://sure.example.com", stdin: "", env: env
      )

      assert_equal 2, result.status
      assert_includes result.stderr, "--api-key-file"
      assert_includes result.stderr, "--api-key-stdin"
      assert_includes result.stderr, "SURE_API_KEY"
    end
  end

  def test_hidden_prompt_never_echoes_the_key
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      stdin = FakeTTY.new("#{SECRET}\n")

      result = run_cli(
        "auth", "login", "--server", server.url,
        stdin: stdin, stdout: FakeTTY.new, env: env
      )

      assert_equal 0, result.status
      assert_includes result.stderr, "API key: "
      refute_includes result.stdout, SECRET
      refute_includes result.stderr, SECRET
      assert_equal 1, server.received.length
    ensure
      server&.stop
    end
  end

  def test_status_json_reports_identity_key_and_rate_limit_without_the_secret
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body), response(usage_body) ])

      login = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url,
        stdin: SECRET, env: env
      )
      assert_equal 0, login.status

      result = run_cli("auth", "status", "--json", env: env)

      assert_equal 0, result.status
      payload = JSON.parse(result.stdout).fetch("data")
      assert_equal "default", payload["profile"]
      assert_equal server.url, payload["server_url"]
      assert_equal "user@example.com", payload.dig("user", "email")
      assert_equal "CLI login key", payload.dig("api_key", "name")
      assert_equal [ "read" ], payload.dig("api_key", "scopes")
      assert_equal "api_key", payload["authentication_method"]
      assert_equal "file", payload["credential_source"]
      assert_equal "standard", payload.dig("rate_limit", "tier")
      refute_includes result.stdout, SECRET
      refute_includes result.stderr, SECRET
    ensure
      server&.stop
    end
  end

  def test_logout_is_idempotent_and_status_then_exits_three
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      login = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url,
        stdin: SECRET, env: env
      )
      assert_equal 0, login.status

      first = run_cli("auth", "logout", "--json", env: env)
      assert_equal 0, first.status
      assert_equal true, JSON.parse(first.stdout).dig("data", "deleted")
      assert_includes JSON.parse(first.stdout).dig("data", "revocation_guidance"), "Settings"
      refute File.exist?(File.join(xdg, "sure", "credentials.json"))

      second = run_cli("auth", "logout", "--json", env: env)
      assert_equal 0, second.status
      assert_equal false, JSON.parse(second.stdout).dig("data", "deleted")

      status = run_cli("auth", "status", "--json", env: env)
      assert_equal 3, status.status
    ensure
      server&.stop
    end
  end

  def test_status_reports_an_environment_credential
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      result = run_cli(
        "auth", "status", "--server", server.url, "--json",
        env: env.merge("SURE_API_KEY" => SECRET)
      )

      assert_equal 0, result.status
      assert_equal "environment", JSON.parse(result.stdout).dig("data", "credential_source")
      refute_includes result.stdout, SECRET
    ensure
      server&.stop
    end
  end

  def test_a_read_only_key_blocks_a_write_before_any_request
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      login = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url,
        stdin: SECRET, env: env
      )
      assert_equal 0, login.status
      requests_before = server.received.length

      result = run_cli(
        "api", "POST", "/api/v1/tags", "--data", "{}", "--yes", env: env
      )

      assert_equal 3, result.status
      assert_includes result.stderr, "read-only"
      assert_equal requests_before, server.received.length
    ensure
      server&.stop
    end
  end

  def test_an_unreadable_ca_bundle_exits_two_before_any_request
    with_temp_config_home do |env, home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      result = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url,
        "--ca-bundle", File.join(home, "missing-ca.pem"),
        stdin: SECRET, env: env
      )

      assert_equal 2, result.status
      assert_includes result.stderr, "not readable"
      assert_empty server.received
    ensure
      server&.stop
    end
  end

  def test_a_readable_ca_bundle_reaches_the_login_probe_profile
    with_temp_config_home do |env, home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      ca = File.join(home, "ca.pem")
      File.write(ca, "PEM")

      result = nil
      profiles = with_captured_probe_profiles do
        result = run_cli(
          "auth", "login", "--api-key-stdin", "--server", server.url,
          "--ca-bundle", ca, stdin: SECRET, env: env
        )
      end

      assert_equal 0, result.status
      assert_equal [ ca ], profiles.map(&:ca_bundle)
      assert_equal :flag, profiles.first.sources[:ca_bundle]
      assert profiles.first.tls_verify
    ensure
      server&.stop
    end
  end

  def test_insecure_reaches_the_login_probe_profile_and_warns
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      result = nil
      profiles = with_captured_probe_profiles do
        result = run_cli(
          "auth", "login", "--api-key-stdin", "--server", server.url,
          "--insecure", stdin: SECRET, env: env
        )
      end

      assert_equal 0, result.status
      refute profiles.first.tls_verify
      assert_includes result.stderr, "TLS verification is disabled"
    ensure
      server&.stop
    end
  end

  def test_a_profile_tls_verify_false_is_honored_by_login_without_a_flag
    with_temp_config_home do |env, _home, _xdg|
      paths = paths_for(env)
      write_config(paths, {
        "schema_version" => 1,
        "default_profile" => "default",
        "profiles" => { "default" => {
          "server_url" => "https://profile.example.com", "tls_verify" => false
        } }
      })
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      result = nil
      profiles = with_captured_probe_profiles do
        result = run_cli(
          "auth", "login", "--api-key-stdin", "--server", server.url,
          stdin: SECRET, env: env
        )
      end

      assert_equal 0, result.status
      refute profiles.first.tls_verify
      assert_equal :profile, profiles.first.sources[:tls_verify]
    ensure
      server&.stop
    end
  end

  def test_environment_ca_bundle_with_insecure_flag_exits_two
    with_temp_config_home do |env, home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      ca = File.join(home, "ca.pem")
      File.write(ca, "PEM")

      result = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url, "--insecure",
        stdin: SECRET, env: env.merge("SURE_CA_BUNDLE" => ca)
      )

      assert_equal 2, result.status
      assert_includes result.stderr, "--ca-bundle"
      assert_includes result.stderr, "--insecure"
      assert_empty server.received
    ensure
      server&.stop
    end
  end

  def test_quiet_stores_the_key_without_the_plaintext_warning
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])

      result = run_cli(
        "auth", "login", "--api-key-stdin", "--server", server.url, "--quiet",
        stdin: SECRET, env: env
      )

      assert_equal 0, result.status
      refute_includes result.stderr, "warning:"
      config = YAML.safe_load_file(File.join(xdg, "sure", "config.yml"))
      assert_equal "file", config.dig("profiles", "default", "credential_store")
      assert File.exist?(File.join(xdg, "sure", "credentials.json"))
    ensure
      server&.stop
    end
  end

  def test_auth_accepts_verbose_and_no_color_and_rejects_quiet_with_verbose
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body), response(usage_body) ])
      auth_env = env.merge("SURE_API_KEY" => SECRET)

      verbose = run_cli(
        "auth", "status", "--server", server.url, "--verbose", "--json", env: auth_env
      )
      assert_equal 0, verbose.status

      no_color = run_cli(
        "auth", "status", "--server", server.url, "--no-color", "--json", env: auth_env
      )
      assert_equal 0, no_color.status

      conflict = run_cli(
        "auth", "status", "--server", server.url, "--quiet", "--verbose", "--json", env: auth_env
      )
      assert_equal 2, conflict.status
      assert_includes conflict.stderr, "quiet"
      assert_includes conflict.stderr, "verbose"
    ensure
      server&.stop
    end
  end

  private

  # Records the profile each HTTP::Client is built with, then builds the real
  # client. Proves what the login probe actually received without a mock server
  # that hides TLS settings.
  def with_captured_probe_profiles
    profiles = []
    original = Sure::HTTP::Client.method(:new)
    replacement = lambda do |**kwargs|
      profiles << kwargs[:profile]
      original.call(**kwargs)
    end

    Sure::HTTP::Client.stub(:new, replacement) { yield }

    profiles
  end

  def response(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body }
  end

  def usage_body(scopes: [ "read" ])
    JSON.generate({
      "api_key" => {
        "name" => "CLI login key",
        "scopes" => scopes,
        "last_used_at" => "2026-10-31T12:00:00Z",
        "created_at" => "2026-10-30T09:00:00Z"
      },
      "rate_limit" => {
        "tier" => "standard",
        "limit" => 100,
        "current_count" => 1,
        "remaining" => 99,
        "reset_in_seconds" => 3600,
        "reset_at" => "2026-10-31T13:00:00Z"
      },
      "user" => {
        "email" => "user@example.com",
        "first_name" => "Ada",
        "last_name" => "Lovelace"
      }
    })
  end
end

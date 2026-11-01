# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class DoctorRunnerTest < Minitest::Test
  include TempConfig

  SERVER = "https://sure.example.com"

  def setup
    WebMock.reset!
    WebMock.allow_net_connect!
  end

  def teardown
    WebMock.disable_net_connect!
  end

  def test_a_healthy_profile_passes_every_check
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))
      write_credential(env, SERVER, "test-key")
      stub_usage_ok
      stub_accounts_ok

      results, code = runner(env).run

      assert_equal 0, code
      assert results.all? { |result| %i[pass warn].include?(result.status) }
      assert_equal true, results.find { |result| result.id == "credential" }.warn?
      assert_requested :get, "#{SERVER}/api/v1/usage", times: 1
      assert_requested :get, "#{SERVER}/api/v1/accounts?per_page=1", times: 1
    end
  end

  def test_a_bad_url_fails_before_any_network_call
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for("ftp://sure.example.com"))

      results, code = runner(env).run

      assert_equal 2, code
      assert results.find { |result| result.id == "profile" }.fail?
      assert_no_requests
    end
  end

  def test_a_rejected_key_exits_three_and_skips_authenticated_checks
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))
      write_credential(env, SERVER, "test-key")
      stub_request(:get, "#{SERVER}/api/v1/usage")
        .to_return(status: 401, headers: { "Content-Type" => "application/json", "Date" => now.httpdate },
                   body: '{"error":"unauthorized"}')

      results, code = runner(env).run

      assert_equal 3, code
      assert results.find { |result| result.id == "connectivity" }.pass?
      assert results.find { |result| result.id == "authentication" }.fail?
      assert results.find { |result| result.id == "scope" }.skip?
      assert results.find { |result| result.id == "capability" }.skip?
      assert results.find { |result| result.id == "clock" }.pass?
      assert_not_requested :get, "#{SERVER}/api/v1/accounts?per_page=1"
      assert_requested :get, "#{SERVER}/api/v1/usage", times: 1
    end
  end

  def test_a_tls_failure_exits_eight
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))
      write_credential(env, SERVER, "test-key")
      stub_request(:get, "#{SERVER}/api/v1/usage")
        .to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))

      results, code = runner(env).run

      assert_equal 8, code
      assert results.find { |result| result.id == "connectivity" }.fail?
      assert results.find { |result| result.id == "authentication" }.skip?
    end
  end

  def test_no_credential_fails_the_credential_check_and_skips_dependents
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))

      results, code = runner(env).run

      assert_equal 3, code
      assert results.find { |result| result.id == "credential" }.fail?
      assert_includes results.find { |result| result.id == "credential" }.fix, "sure auth login"
      %w[connectivity authentication scope capability clock rate_limit].each do |id|
        assert results.find { |result| result.id == id }.skip?, "expected #{id} to skip"
      end
      assert_no_requests
    end
  end

  def test_no_config_file_is_a_check_one_failure_not_an_uncaught_error
    with_temp_config_home do |env|
      results, code = runner(env).run

      assert_equal 1, code
      config = results.find { |result| result.id == "config" }
      assert config.fail?
      assert_includes config.fix, "sure auth login"
      assert results.drop(1).all?(&:skip?)
    end
  end

  def test_a_group_readable_config_file_names_the_chmod_fix
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for(SERVER), mode: 0o644)

      results, code = runner(env).run

      assert_equal 1, code
      config = results.find { |result| result.id == "config" }
      assert config.fail?
      assert_includes config.fix, "chmod 600"
    end
  end

  def test_a_capability_401_exits_three
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))
      write_credential(env, SERVER, "test-key")
      stub_usage_ok
      stub_request(:get, "#{SERVER}/api/v1/accounts?per_page=1")
        .to_return(status: 401, headers: { "Content-Type" => "application/json" }, body: "{}")

      results, code = runner(env).run

      assert_equal 3, code
      assert results.find { |result| result.id == "capability" }.fail?
    end
  end

  def test_clock_skew_over_five_minutes_fails
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))
      write_credential(env, SERVER, "test-key")
      stub_request(:get, "#{SERVER}/api/v1/usage")
        .to_return(status: 200, headers: { "Content-Type" => "application/json", "Date" => (now - 400).httpdate },
                   body: usage_body)
      stub_accounts_ok

      results, code = runner(env).run

      assert_equal 1, code
      clock = results.find { |result| result.id == "clock" }
      assert clock.fail?
      assert_includes clock.detail, "400"
    end
  end

  def test_a_self_hosted_noop_tier_is_unlimited
    with_temp_config_home do |env|
      write_config(paths_for(env), config_for(SERVER))
      write_credential(env, SERVER, "test-key")
      stub_request(:get, "#{SERVER}/api/v1/usage")
        .to_return(status: 200, headers: { "Content-Type" => "application/json", "Date" => now.httpdate },
                   body: JSON.generate({ "api_key" => { "scopes" => [ "read_write" ] },
                                        "rate_limit" => { "tier" => "noop", "limit" => nil } }))
      stub_accounts_ok

      results, code = runner(env).run

      assert_equal 0, code
      assert results.find { |result| result.id == "rate_limit" }.pass?
    end
  end

  private

  def runner(env, clock: CLITestHelper::FIXED_CLOCK)
    runtime = Sure::CLI::Runtime.new(
      stdin: StringIO.new,
      stdout: StringIO.new,
      stderr: StringIO.new,
      env: env,
      cwd: Dir.pwd,
      clock: clock
    )
    Sure::Doctor::Runner.new(runtime: runtime)
  end

  def now
    CLITestHelper::FIXED_CLOCK
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
                       created_at: now
                     ))
  end

  def stub_usage_ok
    stub_request(:get, "#{SERVER}/api/v1/usage")
      .to_return(status: 200, headers: { "Content-Type" => "application/json", "Date" => now.httpdate },
                 body: usage_body)
  end

  def stub_accounts_ok
    stub_request(:get, "#{SERVER}/api/v1/accounts?per_page=1")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: api_fixture("accounts"))
  end

  def usage_body
    JSON.generate({
      "api_key" => { "scopes" => [ "read_write" ] },
      "rate_limit" => { "tier" => "standard", "limit" => 100, "remaining" => 99 }
    })
  end

  def assert_no_requests
    assert_equal 0, WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
  end
end

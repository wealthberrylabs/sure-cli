# frozen_string_literal: true

require "test_helper"

# The auth header must only ever reach the profile's exact scheme, host, port,
# and path prefix. Two tenants mounted on one origin must not cross-wire keys.
class AuthMiddlewareTest < Minitest::Test
  SECRET = "sk_middleware_secret"
  TENANT = "https://sure.example.com/tenant-a"
  ROOT = "https://sure.example.com"

  def test_a_prefix_profile_sends_the_key_inside_its_own_subtree
    env, app = run_middleware(server: TENANT, url: "#{TENANT}/api/v1/usage")

    assert_equal SECRET, env.request_headers["X-Api-Key"]
    assert_equal 1, app.calls
  end

  def test_a_prefix_profile_accepts_its_exact_base_path
    env, = run_middleware(server: TENANT, url: TENANT)

    assert_equal SECRET, env.request_headers["X-Api-Key"]
  end

  def test_refuses_neighboring_path_prefixes_on_the_same_origin
    [
      "#{ROOT}/tenant-b/api/v1/usage",
      "#{ROOT}/tenant-ab/api/v1/usage",
      "#{ROOT}/api/v1/usage"
    ].each do |url|
      assert_refused(server: TENANT, url: url, expected: TENANT)
    end
  end

  def test_refuses_a_different_origin
    [
      "https://other.example.com/tenant-a/api/v1/usage",
      "http://sure.example.com/tenant-a/api/v1/usage",
      "https://sure.example.com:8443/tenant-a/api/v1/usage"
    ].each do |url|
      assert_refused(server: TENANT, url: url, expected: TENANT)
    end
  end

  def test_a_root_profile_still_sends_the_key_to_every_endpoint
    [ "#{ROOT}/api/v1/usage", "#{ROOT}/sure/api/v1/usage" ].each do |url|
      env, app = run_middleware(server: ROOT, url: url)

      assert_equal SECRET, env.request_headers["X-Api-Key"], "expected the key for #{url}"
      assert_equal 1, app.calls
    end
  end

  def test_a_root_profile_refuses_a_different_origin
    assert_refused(server: ROOT, url: "https://other.example.com/api/v1/usage", expected: ROOT)
  end

  def test_a_root_profile_with_a_trailing_slash_keeps_working
    env, = run_middleware(server: "#{ROOT}/", url: "#{ROOT}/api/v1/usage")

    assert_equal SECRET, env.request_headers["X-Api-Key"]
  end

  def test_the_refusal_never_reaches_the_next_middleware_or_names_the_secret
    app = CapturingApp.new
    error = assert_raises(Sure::Errors::UsageError) do
      middleware(app, server: TENANT).call(env_for("#{ROOT}/tenant-b/api/v1/usage"))
    end

    assert_equal 0, app.calls
    assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
    assert_includes error.message, "tenant-a"
    refute_includes error.message, SECRET
  end

  private

  def assert_refused(server:, url:, expected:)
    app = CapturingApp.new
    error = assert_raises(Sure::Errors::UsageError) do
      middleware(app, server: server).call(env_for(url))
    end

    assert_equal 0, app.calls, "the key must not be attached for #{url}"
    assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
    assert_includes error.message, expected
    refute_includes error.message, SECRET
  end

  def run_middleware(server:, url:)
    app = CapturingApp.new
    env = middleware(app, server: server).call(env_for(url))

    [ env, app ]
  end

  def middleware(app, server:)
    profile = Sure::Config::Profile.new(name: "default", server_url: server)
    Sure::HTTP::AuthMiddleware.new(app, StubProvider.new(SECRET), profile)
  end

  def env_for(url)
    Faraday::Env.new(
      url: URI.parse(url),
      request_headers: Faraday::Utils::Headers.new
    )
  end

  # The terminal middleware: records whether the request made it past auth.
  class CapturingApp
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def call(env)
      @calls += 1
      env
    end
  end

  class StubProvider
    def initialize(secret)
      @secret = secret
    end

    def fetch(_profile)
      [ @secret, :environment ]
    end
  end
end

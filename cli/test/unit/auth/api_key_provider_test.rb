# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class ApiKeyProviderTest < Minitest::Test
  include TempConfig

  class FakeStore < Sure::Auth::Store
    attr_reader :mode, :location, :reads

    def initialize(credential: nil, mode: :file)
      @credential = credential
      @mode = mode
      @location = "fake"
      @reads = 0
    end

    def read(_key)
      @reads += 1
      @credential
    end

    def write(_key, credential)
      @credential = credential
    end

    def delete(_key)
      @credential = nil
    end
  end

  def test_environment_key_wins_without_reading_the_store
    store = FakeStore.new(credential: credential)
    provider = Sure::Auth::ApiKeyProvider.new(
      env: { "SURE_API_KEY" => "abc123" }, store: store
    )

    assert_equal [ "abc123", :environment ], provider.fetch(profile)
    assert_equal 0, store.reads
  end

  def test_store_credential_is_used_when_environment_is_absent
    store = FakeStore.new(credential: credential, mode: :keychain)
    provider = Sure::Auth::ApiKeyProvider.new(env: {}, store: store)

    assert_equal [ "stored-secret", :store ], provider.fetch(profile)
    assert_equal 1, store.reads
  end

  def test_missing_key_raises_exit_three_with_actionable_message
    provider = Sure::Auth::ApiKeyProvider.new(env: {}, store: FakeStore.new)

    error = assert_raises(Sure::Errors::AuthenticationError) { provider.fetch(profile) }

    assert_includes error.message, "sure auth login"
    assert_includes error.message, "SURE_API_KEY"
    assert_equal Sure::Errors::ExitCodes::AUTHENTICATION, error.exit_code
  end

  def test_newline_in_environment_key_is_a_usage_error_without_echoing_the_value
    provider = Sure::Auth::ApiKeyProvider.new(
      env: { "SURE_API_KEY" => "abc\n123" }, store: FakeStore.new
    )

    error = assert_raises(Sure::Errors::UsageError) { provider.fetch(profile) }

    assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
    assert_includes error.message, "SURE_API_KEY"
    refute_includes error.message, "abc"
    refute_includes error.message, "123"
  end

  def test_rejects_empty_whitespace_and_oversized_environment_keys
    [ "", "   ", "x" * 4097 ].each do |value|
      provider = Sure::Auth::ApiKeyProvider.new(
        env: { "SURE_API_KEY" => value }, store: FakeStore.new
      )

      error = assert_raises(Sure::Errors::UsageError) { provider.fetch(profile) }
      assert_includes error.message, "SURE_API_KEY"
    end
  end

  def test_rejects_a_three_byte_environment_key_without_echoing_it
    provider = Sure::Auth::ApiKeyProvider.new(
      env: { "SURE_API_KEY" => "zq7" }, store: FakeStore.new
    )

    error = assert_raises(Sure::Errors::UsageError) { provider.fetch(profile) }

    assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
    assert_includes error.message, "at least 4 bytes"
    refute_includes error.message, "zq7"
  end

  def test_rejects_a_three_byte_stored_credential_and_says_to_log_in_again
    store = FakeStore.new(credential: credential(secret: "zq7"))
    provider = Sure::Auth::ApiKeyProvider.new(env: {}, store: store)

    error = assert_raises(Sure::Errors::UsageError) { provider.fetch(profile) }

    assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
    assert_includes error.message, "sure auth login"
    refute_includes error.message, "zq7"
  end

  def test_a_four_byte_key_is_accepted_and_maskable
    provider = Sure::Auth::ApiKeyProvider.new(
      env: { "SURE_API_KEY" => "zq7x" }, store: FakeStore.new
    )

    secret, source = provider.fetch(profile)

    assert_equal [ "zq7x", :environment ], [ secret, source ]
    refute_includes Sure::Redactor.new(active_secret: secret).redact_value("server said #{secret}"), secret
  end

  def test_credential_inspect_and_to_s_redact_the_secret
    rendered = credential.inspect

    assert_includes rendered, "[REDACTED]"
    refute_includes rendered, "stored-secret"
    assert_equal rendered, credential.to_s
  end

  def test_provider_inspect_redacts_the_environment_key
    provider = Sure::Auth::ApiKeyProvider.new(
      env: { "SURE_API_KEY" => "abc123" }, store: FakeStore.new
    )

    assert_includes provider.inspect, "[REDACTED]"
    refute_includes provider.inspect, "abc123"
  end

  def test_credential_key_is_service_scoped_and_origin_fingerprinted
    key = Sure::Auth::CredentialKey.new(
      profile: "default", origin: "https://sure.example.com/sure"
    )

    assert_equal "sure-cli", key.service
    assert_match(/\Adefault@[0-9a-f]{16}\z/, key.account)
    assert_equal "Sure CLI: default (sure.example.com)", key.label
    assert_equal 16, key.origin_fingerprint.length
  end

  def test_credential_key_ignores_default_ports_but_not_path_prefixes
    with_port = Sure::Auth::CredentialKey.new(profile: "p", origin: "https://host:443/sure")
    without_port = Sure::Auth::CredentialKey.new(profile: "p", origin: "https://host/sure")
    other_path = Sure::Auth::CredentialKey.new(profile: "p", origin: "https://host/other")

    assert_equal without_port.account, with_port.account
    refute_equal without_port.account, other_path.account
  end

  def test_null_store_is_a_safe_read_miss_and_fails_writes_loudly
    store = Sure::Auth::NullStore.new
    key = Sure::Auth::CredentialKey.new(profile: "default", origin: "https://host")

    assert_nil store.read(key)
    assert_equal :file, store.mode
    assert_equal "unavailable", store.location

    assert_raises(Sure::Errors::GeneralError) { store.write(key, credential) }
    assert_raises(Sure::Errors::GeneralError) { store.delete(key) }
  end

  def test_environment_key_builds_without_real_storage
    provider = Sure::Auth::ApiKeyProvider.new(
      env: { "SURE_API_KEY" => "abc123" }, store: Sure::Auth::NullStore.new
    )

    assert_equal [ "abc123", :environment ], provider.fetch(profile)
  end

  def test_context_credential_source_tracks_store_mode
    with_store(store: FakeStore.new(credential: credential, mode: :file)) do |context|
      assert_equal :file, context.credential_source
      assert context.scopes_trusted?
    end

    with_store(store: FakeStore.new(credential: credential, mode: :keychain)) do |context|
      assert_equal :keychain, context.credential_source
    end

    with_store(env: { "SURE_API_KEY" => "abc123" }, store: FakeStore.new) do |context|
      assert_equal :environment, context.credential_source
      refute context.scopes_trusted?
    end
  end

  def test_context_inspect_redacts_the_api_key
    with_store(env: { "SURE_API_KEY" => "abc123" }, store: FakeStore.new) do |context|
      assert_equal "abc123", context.api_key
      assert_equal "https://sure.example.com/sure/api/v1/usage",
                   context.url_builder.join("/api/v1/usage")

      refute_includes context.inspect, "abc123"
      assert_includes context.inspect, "[REDACTED]"
    end
  end

  private

  def profile(server_url: "https://sure.example.com/sure")
    Sure::Config::Profile.new(name: "default", server_url: server_url)
  end

  def credential(secret: "stored-secret")
    Sure::Auth::Credential.new(
      kind: :api_key,
      secret: secret,
      server_url: "https://sure.example.com/sure",
      created_at: CLITestHelper::FIXED_CLOCK
    )
  end

  def with_store(env: {}, store: nil)
    with_temp_config_home do |base_env|
      runtime = Sure::CLI::Runtime.new(
        stdin: StringIO.new,
        stdout: StringIO.new,
        stderr: StringIO.new,
        env: base_env.merge(env),
        cwd: Dir.pwd,
        clock: CLITestHelper::FIXED_CLOCK
      )
      context = Sure::CLI::Context.new(
        runtime: runtime,
        options: { server: "https://sure.example.com/sure" },
        store: store
      )
      yield context
    end
  end
end

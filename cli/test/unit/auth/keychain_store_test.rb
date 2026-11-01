# frozen_string_literal: true

require "test_helper"
require "support/fake_command_runner"

class KeychainStoreTest < Minitest::Test
  SECRET = "sk_keychain_secret"

  def setup
    @runner = FakeCommandRunner.new
    @key = Sure::Auth::CredentialKey.new(
      profile: "default", origin: "https://sure.example.com/sure"
    )
  end

  def test_mac_read_strips_exactly_one_trailing_newline
    @runner.enqueue("security", stdout: "#{SECRET}\n\n")

    credential = Sure::Auth::MacKeychainStore.new(runner: @runner).read(@key)

    assert_equal "#{SECRET}\n", credential.secret
    assert_equal "https://sure.example.com/sure", credential.server_url
  end

  def test_mac_read_returns_nil_when_the_item_is_absent
    @runner.enqueue("security", stderr: "could not be found", success: false)

    assert_nil Sure::Auth::MacKeychainStore.new(runner: @runner).read(@key)
  end

  def test_mac_write_sends_the_secret_on_stdin_and_verifies_the_read_back
    @runner.enqueue("security", success: true) # add-generic-password
    @runner.enqueue("security", stdout: "#{SECRET}\n") # find-generic-password
    store = Sure::Auth::MacKeychainStore.new(runner: @runner)

    store.write(@key, credential)

    write_call, read_call = @runner.calls
    assert_equal "add-generic-password", write_call.arguments.first
    assert_equal SECRET, write_call.stdin_data
    refute_includes write_call.arguments, SECRET
    assert_equal "find-generic-password", read_call.arguments.first
    assert_nil read_call.stdin_data
  end

  def test_mac_write_fails_when_the_read_back_does_not_match
    @runner.enqueue("security", success: true)
    @runner.enqueue("security", stdout: "different\n")
    store = Sure::Auth::MacKeychainStore.new(runner: @runner)

    error = assert_raises(Sure::Auth::StoreError) { store.write(@key, credential) }
    assert_includes error.message, "did not return the stored credential"
  end

  def test_secret_service_read_uses_the_documented_attributes
    @runner.enqueue("secret-tool", stdout: "#{SECRET}\n")
    store = Sure::Auth::SecretServiceStore.new(
      runner: @runner, env: { "DBUS_SESSION_BUS_ADDRESS" => "unix:path=/run/bus" }
    )

    credential = store.read(@key)

    assert_equal SECRET, credential.secret
    call = @runner.calls.first
    assert_equal "lookup", call.arguments.first
    assert_equal(
      [ "service", "sure-cli", "profile", "default", "origin", @key.origin_fingerprint ],
      call.arguments.drop(1)
    )
  end

  def test_secret_service_write_sends_the_secret_on_stdin
    @runner.enqueue("secret-tool", success: true)
    store = Sure::Auth::SecretServiceStore.new(
      runner: @runner, env: { "DBUS_SESSION_BUS_ADDRESS" => "unix:path=/run/bus" }
    )

    store.write(@key, credential)

    call = @runner.calls.first
    assert_equal "store", call.arguments.first
    assert_includes call.arguments, "--label"
    assert_equal SECRET, call.stdin_data
    refute_includes call.arguments, SECRET
  end

  def test_secret_service_delete_clears_the_matching_attributes
    @runner.enqueue("secret-tool", success: true)
    store = Sure::Auth::SecretServiceStore.new(
      runner: @runner, env: { "DBUS_SESSION_BUS_ADDRESS" => "unix:path=/run/bus" }
    )

    store.delete(@key)

    assert_equal "clear", @runner.calls.first.arguments.first
  end

  def test_secret_service_is_unavailable_without_a_session_bus
    store = Sure::Auth::SecretServiceStore.new(runner: @runner, env: {})

    refute store.available?
    assert_equal 0, @runner.calls.length
  end

  def test_secret_service_is_unavailable_without_a_helper
    runner = Sure::Auth::CommandRunner.new(env: { "PATH" => "" })
    store = Sure::Auth::SecretServiceStore.new(
      runner: runner, env: { "DBUS_SESSION_BUS_ADDRESS" => "unix:path=/run/bus" }
    )

    refute store.available?
  end

  private

  def credential
    Sure::Auth::Credential.new(
      kind: :api_key,
      secret: SECRET,
      server_url: "https://sure.example.com/sure",
      created_at: CLITestHelper::FIXED_CLOCK
    )
  end
end

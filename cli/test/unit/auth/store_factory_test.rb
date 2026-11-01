# frozen_string_literal: true

require "test_helper"
require "support/fake_store"
require "support/fake_keychain"

class StoreFactoryTest < Minitest::Test
  def test_explicit_file_store_never_touches_the_keychain
    keychain = FakeKeychain.new(available: true)
    file = FakeStore.new
    factory = build_factory(credential_store: "file", keychain: keychain, file: file)

    assert_equal :file, factory.mode
    factory.write(key, credential)

    assert_equal 1, file.writes.length
    assert_empty keychain.writes
  end

  def test_auto_detects_an_available_keychain
    keychain = FakeKeychain.new(available: true)
    file = FakeStore.new
    factory = build_factory(keychain: keychain, file: file)

    assert_equal :keychain, factory.mode
    assert_nil factory.warning
    assert_equal :keychain, factory.write(key, credential)
    assert_equal 1, keychain.writes.length
    assert_empty file.writes
  end

  def test_missing_keychain_falls_back_to_the_file_with_a_warning
    keychain = FakeKeychain.new(available: false)
    file = FakeStore.new
    factory = build_factory(keychain: keychain, file: file)

    assert_equal :file, factory.mode
    assert_includes factory.warning, "keychain is unavailable"
    assert_equal :file, factory.write(key, credential)
    assert_equal 1, file.writes.length
  end

  def test_keychain_write_failure_switches_to_the_file
    keychain = FakeKeychain.new(available: true, fail_write: "access denied")
    file = FakeStore.new
    factory = build_factory(keychain: keychain, file: file)

    assert_equal :keychain, factory.mode
    assert_equal :file, factory.write(key, credential)

    assert_equal :file, factory.mode
    assert_includes factory.warning, "access denied"
    assert_equal 1, file.writes.length
  end

  def test_keychain_miss_falls_back_to_an_existing_file_copy
    keychain = FakeKeychain.new(available: true)
    file = FakeStore.new
    file.write(key, credential)
    factory = build_factory(keychain: keychain, file: file)

    assert_equal :keychain, factory.mode
    assert_equal credential.secret, factory.read(key).secret
  end

  def test_keychain_miss_without_a_file_copy_is_nil
    keychain = FakeKeychain.new(available: true)
    factory = build_factory(keychain: keychain, file: FakeStore.new)

    assert_equal :keychain, factory.mode
    assert_nil factory.read(key)
  end

  def test_keychain_read_failure_uses_an_existing_file_copy
    keychain = FakeKeychain.new(available: true, fail_read: "keychain locked")
    file = FakeStore.new
    file.write(key, credential)
    factory = build_factory(keychain: keychain, file: file)

    assert_equal :keychain, factory.mode
    assert_equal credential.secret, factory.read(key).secret
  end

  def test_keychain_read_failure_without_a_copy_is_actionable
    keychain = FakeKeychain.new(available: true, fail_read: "keychain locked")
    factory = build_factory(keychain: keychain, file: FakeStore.new)

    error = assert_raises(Sure::Errors::AuthenticationError) { factory.read(key) }

    assert_includes error.message, "sure auth login"
    assert_equal Sure::Errors::ExitCodes::AUTHENTICATION, error.exit_code
  end

  def test_delete_removes_the_keychain_item_and_the_file_copy
    keychain = FakeKeychain.new(available: true)
    file = FakeStore.new
    keychain.write(key, credential)
    file.write(key, credential)
    factory = build_factory(keychain: keychain, file: file)

    factory.delete(key)

    assert_equal [ key.account ], keychain.deletes
    assert_equal [ key.account ], file.deletes
  end

  def test_reset_restores_auto_detection
    keychain = FakeKeychain.new(available: true, fail_write: "denied")
    file = FakeStore.new
    factory = build_factory(keychain: keychain, file: file)

    factory.write(key, credential)
    assert_equal :file, factory.mode

    keychain.available = true
    keychain.fail_write = nil
    factory.reset!

    assert_equal :keychain, factory.mode
  end

  def test_unknown_platform_uses_the_file_store
    factory = Sure::Auth::StoreFactory.new(
      profile: profile,
      env: {},
      platform: :other,
      file_store: FakeStore.new
    )

    assert_equal :file, factory.mode
    assert_includes factory.warning, "keychain is unavailable"
  end

  private

  def build_factory(credential_store: nil, keychain:, file:)
    Sure::Auth::StoreFactory.new(
      profile: profile(credential_store: credential_store),
      env: {},
      platform: :linux,
      keychain_store: keychain,
      file_store: file
    )
  end

  def profile(credential_store: nil)
    Sure::Config::Profile.new(
      name: "default",
      server_url: "https://sure.example.com/sure",
      credential_store: credential_store
    )
  end

  def key
    Sure::Auth::CredentialKey.new(profile: "default", origin: "https://sure.example.com/sure")
  end

  def credential
    Sure::Auth::Credential.new(
      kind: :api_key,
      secret: "sk_test_secret",
      server_url: "https://sure.example.com/sure",
      created_at: CLITestHelper::FIXED_CLOCK
    )
  end
end

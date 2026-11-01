# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class FileStoreTest < Minitest::Test
  include TempConfig

  SECRET = "sk_test_secret_value"
  SERVER = "https://sure.example.com/sure"

  def test_write_creates_a_private_file_a_lock_and_the_documented_document
    with_store do |store, _paths|
      store.write(key, credential)

      file_mode = File.stat(store.path).mode & 0o777
      lock_mode = File.stat(store.lock_path).mode & 0o777
      directory_mode = File.stat(File.dirname(store.path)).mode & 0o777

      assert_equal 0o600, file_mode
      assert_equal 0o600, lock_mode
      assert_equal 0o700, directory_mode

      document = JSON.parse(File.read(store.path))
      assert_equal 1, document["schema_version"]
      assert_equal SECRET, document.dig("credentials", key.account, "secret")
      assert_equal SERVER, document.dig("credentials", key.account, "server_url")
    end
  end

  def test_read_returns_the_credential_or_nil
    with_store do |store, _paths|
      assert_nil store.read(key)

      store.write(key, credential)
      loaded = store.read(key)

      assert_equal SECRET, loaded.secret
      assert_equal :api_key, loaded.kind
      assert_equal SERVER, loaded.server_url
      assert_equal CLITestHelper::FIXED_CLOCK, loaded.created_at
    end
  end

  def test_writes_merge_profiles_instead_of_overwriting
    with_store do |store, _paths|
      staging = Sure::Auth::CredentialKey.new(profile: "staging", origin: "https://staging.example.com")

      store.write(key, credential)
      store.write(staging, credential(secret: "other-secret"))

      document = JSON.parse(File.read(store.path))
      assert_equal SECRET, document.dig("credentials", key.account, "secret")
      assert_equal "other-secret", document.dig("credentials", staging.account, "secret")
    end
  end

  def test_delete_removes_only_the_target_then_removes_the_empty_file
    with_store do |store, _paths|
      staging = Sure::Auth::CredentialKey.new(profile: "staging", origin: "https://staging.example.com")
      store.write(key, credential)
      store.write(staging, credential(secret: "other-secret"))

      assert store.delete(key)
      assert File.exist?(store.path)
      assert_nil store.read(key)
      refute_nil store.read(staging)

      assert store.delete(staging)
      refute File.exist?(store.path)
    end
  end

  def test_delete_profile_removes_every_origin_for_that_profile
    with_store do |store, _paths|
      other = Sure::Auth::CredentialKey.new(profile: "default", origin: "https://other.example.com")

      store.write(key, credential)
      store.write(other, credential(secret: "other-secret"))

      assert_equal 2, store.delete_profile("default")
      refute File.exist?(store.path)
    end
  end

  def test_read_refuses_a_group_or_world_readable_file
    with_store do |store, _paths|
      store.write(key, credential)
      File.chmod(0o644, store.path)

      error = assert_raises(Sure::Errors::UsageError) { store.read(key) }
      assert_includes error.message, "chmod 600"
      assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
    end
  end

  def test_read_refuses_a_symlinked_credentials_file
    with_store do |store, _paths|
      FileUtils.mkdir_p(File.dirname(store.path))
      target = File.join(File.dirname(store.path), "elsewhere.json")
      File.write(target, JSON.generate({ "schema_version" => 1, "credentials" => {} }))
      File.symlink(target, store.path)

      error = assert_raises(Sure::Errors::UsageError) { store.read(key) }
      assert_includes error.message, "symlink"
    end
  end

  def test_write_refuses_a_symlinked_lock_file
    with_store do |store, _paths|
      FileUtils.mkdir_p(File.dirname(store.lock_path))
      File.symlink("/tmp/surely-not-here", store.lock_path)

      error = assert_raises(Sure::Errors::UsageError) { store.write(key, credential) }
      assert_includes error.message, "symlink"
    end
  end

  def test_lock_is_released_after_a_write
    with_store do |store, _paths|
      store.write(key, credential)

      File.open(store.lock_path, File::RDWR) do |lock|
        assert lock.flock(File::LOCK_EX | File::LOCK_NB)
        lock.flock(File::LOCK_UN)
      end
    end
  end

  def test_invalid_documents_are_rejected
    with_store do |store, _paths|
      FileUtils.mkdir_p(File.dirname(store.path))
      File.write(store.path, "not json")
      File.chmod(0o600, store.path)

      error = assert_raises(Sure::Errors::UsageError) { store.read(key) }
      assert_includes error.message, "not valid JSON"
    end
  end

  private

  def with_store
    with_temp_config_home do |env|
      paths = Sure::Config::Paths.new(env: env)
      yield Sure::Auth::FileStore.new(paths: paths), paths
    end
  end

  def key
    Sure::Auth::CredentialKey.new(profile: "default", origin: SERVER)
  end

  def credential(secret: SECRET)
    Sure::Auth::Credential.new(
      kind: :api_key,
      secret: secret,
      server_url: SERVER,
      created_at: CLITestHelper::FIXED_CLOCK
    )
  end
end

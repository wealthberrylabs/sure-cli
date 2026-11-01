# frozen_string_literal: true

require "test_helper"
require "support/temp_config"
require "support/fake_keychain"

# `sure auth logout` must report what it actually deleted. A credential stored
# only in the 0600 file is real even while an OS keychain is available, and a
# second run must stay idempotent without raising.
class LogoutTest < Minitest::Test
  include TempConfig

  SECRET = "sk_logout_secret"
  SERVER = "https://sure.example.com/sure"

  def test_reports_a_file_only_credential_as_deleted_while_a_keychain_is_available
    with_temp_config_home do |env, _home, xdg|
      factory, _file, keychain = build_factory(env)
      write_config(loader_paths(env), profile_config)
      file_store(env).write(key, credential)

      result = logout(env, factory)

      assert_equal true, result.data["deleted"]
      assert_equal "default", result.data["profile"]
      assert_equal SERVER, result.data["server_url"]
      assert_nil file_store(env).read(key)
      assert_equal [ key.account ], keychain.deletes
      refute File.exist?(File.join(xdg, "sure", "credentials.json"))
    end
  end

  def test_a_second_logout_is_idempotent
    with_temp_config_home do |env, _home, _xdg|
      factory, = build_factory(env)
      write_config(loader_paths(env), profile_config)

      first = logout(env, factory)
      second = logout(env, factory)

      assert_equal false, first.data["deleted"]
      assert_equal false, second.data["deleted"]
    end
  end

  def test_a_second_logout_after_a_file_credential_is_deleted_reports_false
    with_temp_config_home do |env, _home, _xdg|
      factory, = build_factory(env)
      write_config(loader_paths(env), profile_config)
      file_store(env).write(key, credential)

      first = logout(env, factory)
      second = logout(env, factory)

      assert_equal true, first.data["deleted"]
      assert_equal false, second.data["deleted"]
    end
  end

  def test_a_keychain_read_failure_still_finds_and_deletes_the_file_copy
    with_temp_config_home do |env, _home, _xdg|
      factory, = build_factory(env, keychain: FakeKeychain.new(
        available: true, fail_read: "keychain locked"
      ))
      write_config(loader_paths(env), profile_config)
      file_store(env).write(key, credential)

      result = logout(env, factory)

      assert_equal true, result.data["deleted"]
      assert_nil file_store(env).read(key)
    end
  end

  def test_no_rendered_value_or_warning_contains_the_secret
    with_temp_config_home do |env, _home, _xdg|
      factory, = build_factory(env)
      write_config(loader_paths(env), profile_config)
      file_store(env).write(key, credential)

      result = logout(env, factory)
      rendered = JSON.generate(result.data)
      warnings = result.meta[:warnings].join(" ")

      refute_includes rendered, SECRET
      refute_includes warnings, SECRET
    end
  end

  private

  def build_factory(env, keychain: FakeKeychain.new(available: true))
    file = file_store(env)
    factory = Sure::Auth::StoreFactory.new(
      profile: profile,
      env: env,
      platform: :linux,
      keychain_store: keychain,
      file_store: file
    )
    [ factory, file, keychain ]
  end

  def logout(env, factory)
    Sure::Auth::Logout.new(runtime: runtime(env), store_factory: factory).call
  end

  def runtime(env)
    Sure::CLI::Runtime.new(
      stdin: StringIO.new,
      stdout: StringIO.new,
      stderr: StringIO.new,
      env: env,
      cwd: Dir.pwd,
      clock: CLITestHelper::FIXED_CLOCK
    )
  end

  def loader_paths(env)
    paths_for(env)
  end

  def file_store(env)
    Sure::Auth::FileStore.new(paths: paths_for(env))
  end

  def profile
    Sure::Config::Profile.new(
      name: "default",
      server_url: SERVER,
      credential_store: "keychain"
    )
  end

  def profile_config
    {
      "schema_version" => 1,
      "default_profile" => "default",
      "profiles" => {
        "default" => { "server_url" => SERVER, "credential_store" => "keychain" }
      }
    }
  end

  def key
    Sure::Auth::CredentialKey.new(profile: "default", origin: SERVER)
  end

  def credential
    Sure::Auth::Credential.new(
      kind: :api_key,
      secret: SECRET,
      server_url: SERVER,
      created_at: CLITestHelper::FIXED_CLOCK
    )
  end
end

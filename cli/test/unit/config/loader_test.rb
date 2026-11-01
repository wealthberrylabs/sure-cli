# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class LoaderTest < Minitest::Test
  include TempConfig

  VALID_FIXTURE = File.expand_path("../../fixtures/config/valid.yml", __dir__)
  INVALID_FIXTURE = File.expand_path("../../fixtures/config/invalid_schema.yml", __dir__)

  def test_missing_file_returns_an_empty_schema
    with_temp_config_home do |env|
      data = build_loader(env).load

      assert_equal 1, data["schema_version"]
      assert_equal({}, data["profiles"])
    end
  end

  def test_loads_a_valid_fixture
    with_temp_config_home do |env|
      loader = build_loader(env)
      loader.paths.ensure_directory!
      FileUtils.cp(VALID_FIXTURE, loader.path)
      File.chmod(0o600, loader.path)

      data = loader.load

      assert_equal "default", data["default_profile"]
      assert_equal "https://sure.example.com/sure", data["profiles"]["default"]["server_url"]
      assert_equal [ "read" ], data["profiles"]["default"]["scopes"]
    end
  end

  def test_rejects_unknown_top_level_keys_with_file_and_key
    with_temp_config_home do |env|
      loader = build_loader(env)
      loader.paths.ensure_directory!
      FileUtils.cp(INVALID_FIXTURE, loader.path)
      File.chmod(0o600, loader.path)

      error = assert_raises(Sure::Errors::UsageError) { loader.load }

      assert_includes error.message, loader.path
      assert_includes error.message, "unexpected_key"
    end
  end

  def test_rejects_unknown_profile_keys
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, { "schema_version" => 1, "profiles" => {
        "default" => { "server_url" => "https://sure.example.com", "api_key" => "leak" }
      } })

      error = assert_raises(Sure::Errors::UsageError) { Sure::Config::Loader.new(paths: paths).load }

      assert_includes error.message, "api_key"
      assert_includes error.message, "profile `default`"
    end
  end

  def test_save_creates_private_files_and_deep_merges_profiles
    with_temp_config_home do |env|
      paths = paths_for(env)
      loader = Sure::Config::Loader.new(paths: paths)

      loader.save(
        "default_profile" => "default",
        "profiles" => {
          "default" => { "server_url" => "https://one.example", "scopes" => [ "read" ] }
        }
      )

      assert_equal 0o700, File.stat(paths.directory).mode & 0o777
      assert_equal 0o600, File.stat(loader.path).mode & 0o777

      loader.save("profiles" => { "work" => { "server_url" => "https://two.example" } })

      data = loader.load
      assert_equal %w[default work], data["profiles"].keys.sort
      assert_equal "default", data["default_profile"]
      assert_equal [ "read" ], data["profiles"]["default"]["scopes"]
    end
  end

  def test_saved_config_never_contains_secret_keys
    with_temp_config_home do |env|
      loader = build_loader(env)
      loader.save(
        "profiles" => { "default" => { "server_url" => "https://sure.example.com" } }
      )

      contents = File.read(loader.path)
      %w[SURE_API_KEY api_key token secret].each do |secret_key|
        refute_includes contents, secret_key
      end
    end
  end

  def test_refuses_group_or_world_readable_config
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, { "schema_version" => 1, "profiles" => {} })
      File.chmod(0o644, paths.config_file)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Config::Loader.new(paths: paths).load
      end

      assert_includes error.message, "chmod 600 #{paths.config_file}"
    end
  end

  def test_windows_skips_posix_mode_checks_but_refuses_symlinks
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, { "schema_version" => 1, "profiles" => {} })
      File.chmod(0o644, paths.config_file)

      data = Sure::Config::Loader.new(paths: paths, windows: true).load
      assert_equal({}, data["profiles"])

      target = File.join(File.dirname(paths.directory), "target.yml")
      Sure::Config::AtomicFile.write(target, "schema_version: 1\nprofiles: {}\n")
      File.unlink(paths.config_file)
      File.symlink(target, paths.config_file)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Config::Loader.new(paths: paths, windows: true).load
      end
      assert_includes error.message, "symlink"
    end
  end

  def test_concurrent_saves_preserve_both_profiles_and_release_the_lock
    with_temp_config_home do |env|
      paths = paths_for(env)
      loader_one = Sure::Config::Loader.new(paths: paths)
      loader_two = Sure::Config::Loader.new(paths: paths)
      start = Queue.new

      threads = [
        [ loader_one, "one" ],
        [ loader_two, "two" ]
      ].map do |loader, name|
        Thread.new do
          start.pop
          loader.save("profiles" => { name => { "server_url" => "https://#{name}.example" } })
        end
      end

      2.times { start << true }
      threads.each(&:join)

      data = Sure::Config::Loader.new(paths: paths).load
      assert_equal %w[one two], data["profiles"].keys.sort
      assert_equal 0o600, File.stat(paths.config_lock_file).mode & 0o777

      # The lock is released: another save still succeeds.
      loader_one.save("profiles" => { "three" => { "server_url" => "https://three.example" } })
      assert_includes loader_one.load["profiles"].keys, "three"
    end
  end

  private

  def build_loader(env)
    Sure::Config::Loader.new(paths: paths_for(env))
  end
end

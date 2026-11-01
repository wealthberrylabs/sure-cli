# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class PathsTest < Minitest::Test
  include TempConfig

  def test_uses_absolute_xdg_config_home
    paths = Sure::Config::Paths.new(
      env: { "XDG_CONFIG_HOME" => "/tmp/xdg", "HOME" => "/home/user" }
    )

    assert_equal "/tmp/xdg/sure", paths.directory
  end

  def test_ignores_relative_xdg_config_home
    paths = Sure::Config::Paths.new(
      env: { "XDG_CONFIG_HOME" => "relative/xdg", "HOME" => "/home/user" }
    )

    assert_equal "/home/user/.config/sure", paths.directory
  end

  def test_falls_back_to_home_config
    paths = Sure::Config::Paths.new(env: { "HOME" => "/home/user" })

    assert_equal "/home/user/.config/sure", paths.directory
  end

  def test_uses_appdata_on_windows
    paths = Sure::Config::Paths.new(
      env: { "APPDATA" => "/users/ada/AppData/Roaming", "HOME" => "/users/ada" },
      windows: true
    )

    assert_equal File.join("/users/ada/AppData/Roaming", "sure"), paths.directory
  end

  def test_file_paths_live_inside_the_directory
    paths = Sure::Config::Paths.new(env: { "XDG_CONFIG_HOME" => "/tmp/xdg" })

    assert_equal "/tmp/xdg/sure/config.yml", paths.config_file
    assert_equal "/tmp/xdg/sure/credentials.json", paths.credentials_file
    assert_equal "/tmp/xdg/sure/credentials.lock", paths.lock_file
    assert_equal "/tmp/xdg/sure/config.lock", paths.config_lock_file
  end

  def test_ensure_directory_creates_a_private_directory
    with_temp_config_home do |env|
      paths = paths_for(env)

      paths.ensure_directory!

      assert File.directory?(paths.directory)
      assert_equal 0o700, File.stat(paths.directory).mode & 0o777
    end
  end

  def test_ensure_directory_refuses_a_symlinked_directory
    with_temp_config_home do |env, home, xdg|
      target = File.join(home, "target")
      FileUtils.mkdir_p(target)
      File.symlink(target, File.join(xdg, "sure"))

      error = assert_raises(Sure::Errors::UsageError) { paths_for(env).ensure_directory! }
      assert_includes error.message, "symlink"
    end
  end
end

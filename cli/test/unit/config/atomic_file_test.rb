# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class AtomicFileTest < Minitest::Test
  include TempConfig

  def test_writes_0600_content_inside_a_0700_directory
    with_temp_config_home do |env|
      paths = paths_for(env)
      paths.ensure_directory!

      Sure::Config::AtomicFile.write(paths.config_file, "hello\n")

      assert_equal "hello\n", File.read(paths.config_file)
      assert_equal 0o600, File.stat(paths.config_file).mode & 0o777
      assert_equal 0o700, File.stat(paths.directory).mode & 0o777
    end
  end

  def test_replaces_an_existing_file
    with_temp_config_home do |env|
      paths = paths_for(env)
      paths.ensure_directory!
      Sure::Config::AtomicFile.write(paths.config_file, "old")
      File.chmod(0o644, paths.config_file)

      Sure::Config::AtomicFile.write(paths.config_file, "new")

      assert_equal "new", File.read(paths.config_file)
      assert_equal 0o600, File.stat(paths.config_file).mode & 0o777
    end
  end

  def test_refuses_a_symlinked_target_and_leaves_it_unchanged
    with_temp_config_home do |env, home|
      paths = paths_for(env)
      paths.ensure_directory!
      target = File.join(home, "target")
      File.write(target, "original")
      File.chmod(0o600, target)
      File.symlink(target, paths.config_file)

      assert_raises(Sure::Errors::UsageError) do
        Sure::Config::AtomicFile.write(paths.config_file, "replacement")
      end

      assert_equal "original", File.read(target)
    end
  end

  def test_cleans_up_its_temp_file
    with_temp_config_home do |env|
      paths = paths_for(env)
      paths.ensure_directory!

      Sure::Config::AtomicFile.write(paths.config_file, "content")

      leftovers = Dir.glob(File.join(paths.directory, ".*.tmp-*"))
      assert_empty leftovers
    end
  end
end

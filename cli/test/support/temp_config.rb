# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "yaml"

# Isolated configuration directories for unit tests. Never touches the real
# ~/.config/sure; restores XDG_CONFIG_HOME after the block.
module TempConfig
  def with_temp_config_home
    Dir.mktmpdir("sure-config") do |root|
      home = File.join(root, "home")
      xdg = File.join(root, "xdg")
      FileUtils.mkdir_p(home)
      FileUtils.mkdir_p(xdg, mode: 0o700)

      previous = ENV["XDG_CONFIG_HOME"]
      ENV["XDG_CONFIG_HOME"] = xdg
      begin
        yield({ "HOME" => home, "XDG_CONFIG_HOME" => xdg }, home, xdg)
      ensure
        ENV["XDG_CONFIG_HOME"] = previous
      end
    end
  end

  def paths_for(env)
    Sure::Config::Paths.new(env: env)
  end

  def write_config(paths, data, mode: 0o600)
    paths.ensure_directory!
    Sure::Config::AtomicFile.write(paths.config_file, YAML.dump(data), mode: mode)
  end
end

# frozen_string_literal: true

require "fileutils"
require "pathname"

require_relative "../errors"

module Sure
  module Config
    # Resolves the per-user configuration directory and the files inside it.
    # The directory is private (0700); every file written there is 0600.
    class Paths
      DIRECTORY_NAME = "sure"
      CONFIG_FILE = "config.yml"
      CREDENTIALS_FILE = "credentials.json"
      LOCK_FILE = "credentials.lock"
      CONFIG_LOCK_FILE = "config.lock"

      def initialize(env: ENV, home: nil, windows: nil)
        @env = env
        @home = home || env["HOME"] || Dir.home
        @windows = windows.nil? ? Gem.win_platform? : windows
      end

      attr_reader :env, :home

      def windows?
        @windows
      end

      def directory
        @directory ||= resolve_directory
      end

      def config_file
        File.join(directory, CONFIG_FILE)
      end

      def credentials_file
        File.join(directory, CREDENTIALS_FILE)
      end

      def lock_file
        File.join(directory, LOCK_FILE)
      end

      def config_lock_file
        File.join(directory, CONFIG_LOCK_FILE)
      end

      # Creates the configuration directory with mode 0700. Refuses to treat a
      # symlinked directory as the CLI's own storage.
      def ensure_directory!
        if File.symlink?(directory)
          raise Errors::UsageError, "config directory #{directory} must not be a symlink"
        end

        FileUtils.mkdir_p(directory, mode: 0o700)
        File.chmod(0o700, directory)
        directory
      rescue SystemCallError => e
        raise Errors::UsageError, "cannot create config directory #{directory}: #{e.message}"
      end

      private

      def resolve_directory
        xdg = env["XDG_CONFIG_HOME"]
        return File.join(xdg, DIRECTORY_NAME) if absolute?(xdg)

        return windows_directory if windows?

        File.join(home, ".config", DIRECTORY_NAME)
      end

      def windows_directory
        appdata = env["APPDATA"]
        return File.join(appdata, DIRECTORY_NAME) if present?(appdata)

        File.join(home, "AppData", "Roaming", DIRECTORY_NAME)
      end

      def absolute?(value)
        present?(value) && Pathname.new(value).absolute?
      end

      def present?(value)
        value.is_a?(String) && !value.empty?
      end
    end
  end
end

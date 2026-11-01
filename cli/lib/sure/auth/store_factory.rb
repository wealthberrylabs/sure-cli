# frozen_string_literal: true

require "rbconfig"

require_relative "../config/paths"
require_relative "../errors"
require_relative "command_runner"
require_relative "file_store"
require_relative "mac_keychain_store"
require_relative "secret_service_store"
require_relative "store"

module Sure
  module Auth
    # Chooses one credential backend for a profile and owns the fallback
    # transitions. Keychain-first; when the platform keychain is missing or a
    # write fails, the credential lands in the 0600 file and the caller gets a
    # warning instead of a crash.
    class StoreFactory < Store
      def initialize(profile:, paths: nil, env: ENV, runner: nil, platform: nil,
                     file_store: nil, keychain_store: nil)
        @profile = profile
        @env = env
        @paths = paths || Config::Paths.new(env: env)
        @runner = runner || CommandRunner.new(env: env)
        @platform = platform || detect_platform
        @file_store = file_store || FileStore.new(paths: @paths)
        @keychain_store = keychain_store || build_keychain
        @mode = nil
        @warning = nil
      end

      attr_reader :profile, :env, :runner, :platform, :file_store, :keychain_store, :warning

      # Keychain read failure falls back to an existing file copy only.
      def read(key)
        return file_store.read(key) if mode == :file

        begin
          keychain_store.read(key)
        rescue StoreError => e
          copy = file_store.read(key)
          return copy if copy

          raise Errors::AuthenticationError,
                "cannot read the credential from the OS keychain (#{e.message}); " \
                "run `sure auth login` to store it again"
        end
      end

      # Returns the backend that actually stored the credential (:keychain or
      # :file) so login can persist the truth.
      def write(key, credential)
        if mode == :file
          file_store.write(key, credential)
          return :file
        end

        begin
          keychain_store.write(key, credential)
          :keychain
        rescue StoreError => e
          file_store.write(key, credential)
          @mode = :file
          @warning =
            "the OS keychain is unavailable (#{e.message}); the API key was stored " \
            "in #{file_store.location} with 0600 permissions"
          :file
        end
      end

      # Removes the credential from the configured backend and any file copy.
      def delete(key)
        delete_from_keychain(key)
        file_store.delete(key)
        nil
      end

      # Used by logout when the profile has no server URL, so no keychain
      # identity can be derived.
      def delete_profile(profile_name)
        file_store.delete_profile(profile_name)
      end

      def mode
        @mode ||= resolve_mode
      end

      def location
        mode == :keychain ? keychain_store.location : file_store.location
      end

      # Login restores this if the config write fails after a fallback write.
      def reset!
        @mode = nil
        @warning = nil
        self
      end

      def inspect
        "#<Sure::Auth::StoreFactory profile=#{profile.name.inspect} mode=#{@mode.inspect}>"
      end

      private

      def configured_store
        profile.credential_store.to_s
      end

      def resolve_mode
        case configured_store
        when "file" then :file
        when "keychain" then keychain_available? ? :keychain : file_fallback_mode
        else keychain_available? ? :keychain : file_fallback_mode
        end
      end

      def file_fallback_mode
        unless @warning
          @warning = "the OS keychain is unavailable; the API key will be stored " \
                     "in #{file_store.location} with 0600 permissions"
        end
        :file
      end

      def keychain_available?
        !keychain_store.nil? && keychain_store.available?
      end

      def build_keychain
        case platform
        when :macos then MacKeychainStore.new(runner: runner)
        when :linux then SecretServiceStore.new(runner: runner, env: env)
        end
      end

      def detect_platform
        host = RbConfig::CONFIG["host_os"].to_s
        return :macos if host.match?(/darwin/)
        return :linux if host.match?(/linux/)

        :other
      end

      def delete_from_keychain(key)
        return unless keychain_available?

        keychain_store.delete(key)
      rescue StoreError
        nil
      end
    end
  end
end

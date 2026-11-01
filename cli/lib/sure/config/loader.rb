# frozen_string_literal: true

require "yaml"

require_relative "../errors"
require_relative "atomic_file"
require_relative "paths"

module Sure
  module Config
    # Reads and writes the non-secret profile file. Reads are validated against a
    # closed schema; writes are serialized, private, and atomic so concurrent
    # logins cannot drop each other's profiles.
    class Loader
      SCHEMA_VERSION = 1
      TOP_LEVEL_KEYS = %w[schema_version default_profile profiles].freeze
      PROFILE_KEYS = %w[
        server_url ca_bundle tls_verify open_timeout read_timeout output
        read_only credential_store scopes plaintext_warning_shown
      ].freeze
      CREDENTIAL_STORES = %w[keychain file].freeze
      OUTPUT_FORMATS = %w[table json csv ndjson].freeze

      def self.load(paths = Paths.new, **options)
        new(paths: paths, **options).load
      end

      def initialize(paths: Paths.new, windows: nil)
        @paths = paths
        @windows = windows.nil? ? Gem.win_platform? : windows
      end

      attr_reader :paths

      def windows?
        @windows
      end

      def path
        paths.config_file
      end

      # Returns a normalized Hash with string keys. A missing or empty file is an
      # empty, valid schema rather than an error, so first-run commands work.
      def load
        return empty_config unless File.exist?(path)

        check_path_safety!
        check_permissions!

        data = parse
        return empty_config if data.nil? || data.empty?

        validate!(data)
        normalize(data)
      end

      # Deep-merges `changes` into the current file and writes it atomically
      # under an exclusive lock. The file is re-read inside the lock so a
      # concurrent writer's profiles survive this update.
      def save(changes)
        paths.ensure_directory!
        changes = stringify_keys(changes)

        with_lock do
          merged = deep_merge(load, changes)
          validate!(merged)
          normalized = normalize(merged)
          AtomicFile.write(path, YAML.dump(normalized))
          normalized
        end
      end

      private

      def empty_config
        { "schema_version" => SCHEMA_VERSION, "profiles" => {} }
      end

      def with_lock
        lock_path = paths.config_lock_file
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          File.chmod(0o600, lock_path)
          lock.flock(File::LOCK_EX)
          begin
            yield
          ensure
            lock.flock(File::LOCK_UN)
          end
        end
      rescue SystemCallError => e
        raise Errors::UsageError, "cannot lock config file #{lock_path}: #{e.message}"
      end

      def parse
        YAML.safe_load_file(path, aliases: false)
      rescue Psych::Exception => e
        raise Errors::UsageError, "config #{path} is not valid YAML: #{e.message}"
      end

      def check_path_safety!
        directory = paths.directory
        if File.symlink?(directory)
          raise Errors::UsageError, "config directory #{directory} must not be a symlink"
        end
        return unless File.symlink?(path)

        raise Errors::UsageError, "config file #{path} must not be a symlink"
      end

      def check_permissions!
        return if windows?

        stat = File.stat(path)
        if (stat.mode & 0o077) != 0
          raise Errors::UsageError,
                "config file #{path} is group/world accessible; run `chmod 600 #{path}`"
        end
        return if stat.uid == Process.euid

        raise Errors::UsageError,
              "config file #{path} is not owned by the current user; run `chmod 600 #{path}`"
      end

      def validate!(data)
        unless data.is_a?(Hash)
          raise Errors::UsageError, "config #{path} must be a YAML mapping"
        end

        reject_unknown_keys!(data, TOP_LEVEL_KEYS, "top-level")

        unless data["schema_version"] == SCHEMA_VERSION
          raise Errors::UsageError,
                "config #{path} must set schema_version: #{SCHEMA_VERSION}"
        end

        profiles = data.fetch("profiles", {})
        unless profiles.is_a?(Hash)
          raise Errors::UsageError, "config #{path} key `profiles` must be a mapping"
        end

        if data.key?("default_profile") && !data["default_profile"].is_a?(String)
          raise Errors::UsageError,
                "config #{path} key `default_profile` must be a string"
        end

        profiles.each do |name, attributes|
          validate_profile!(name, attributes)
        end
      end

      def validate_profile!(name, attributes)
        unless attributes.is_a?(Hash)
          raise Errors::UsageError, "config #{path} profile `#{name}` must be a mapping"
        end

        reject_unknown_keys!(attributes, PROFILE_KEYS, "profile `#{name}`")
        validate_types!(name, attributes)
      end

      def validate_types!(name, attributes)
        validate_string!(name, attributes, "server_url")
        validate_string!(name, attributes, "ca_bundle", allow_nil: true)
        validate_boolean!(name, attributes, "tls_verify")
        validate_integer!(name, attributes, "open_timeout")
        validate_integer!(name, attributes, "read_timeout")
        validate_output!(name, attributes)
        validate_boolean!(name, attributes, "read_only")
        validate_credential_store!(name, attributes)
        validate_scopes!(name, attributes)
        validate_boolean!(name, attributes, "plaintext_warning_shown")
      end

      def validate_string!(name, attributes, key, allow_nil: false)
        return unless attributes.key?(key)
        return if allow_nil && attributes[key].nil?
        return if attributes[key].is_a?(String)

        raise Errors::UsageError,
              "config #{path} profile `#{name}` key `#{key}` must be a string"
      end

      def validate_boolean!(name, attributes, key)
        return unless attributes.key?(key)
        return if [ true, false ].include?(attributes[key])

        raise Errors::UsageError,
              "config #{path} profile `#{name}` key `#{key}` must be true or false"
      end

      def validate_integer!(name, attributes, key)
        return unless attributes.key?(key)
        return if attributes[key].is_a?(Integer) && attributes[key].positive?

        raise Errors::UsageError,
              "config #{path} profile `#{name}` key `#{key}` must be a positive integer"
      end

      def validate_output!(name, attributes)
        return unless attributes.key?("output")

        value = attributes["output"]
        return if value.nil? || (value.is_a?(String) && OUTPUT_FORMATS.include?(value))

        raise Errors::UsageError,
              "config #{path} profile `#{name}` key `output` must be one of " \
              "#{OUTPUT_FORMATS.join(', ')}"
      end

      def validate_credential_store!(name, attributes)
        return unless attributes.key?("credential_store")

        value = attributes["credential_store"]
        return if value.nil? || CREDENTIAL_STORES.include?(value)

        raise Errors::UsageError,
              "config #{path} profile `#{name}` key `credential_store` must be " \
              "#{CREDENTIAL_STORES.join(' or ')}"
      end

      def validate_scopes!(name, attributes)
        return unless attributes.key?("scopes")

        value = attributes["scopes"]
        return if value.is_a?(Array) && value.all? { |scope| scope.is_a?(String) }

        raise Errors::UsageError,
              "config #{path} profile `#{name}` key `scopes` must be a list of strings"
      end

      def reject_unknown_keys!(attributes, allowed, context)
        unknown = attributes.keys - allowed
        return if unknown.empty?

        raise Errors::UsageError,
              "config #{path} has unknown #{context} key `#{unknown.first}`"
      end

      def normalize(data)
        normalized = {
          "schema_version" => SCHEMA_VERSION,
          "profiles" => data.fetch("profiles", {}).transform_values { |attributes| attributes.dup }
        }
        if data.key?("default_profile")
          normalized["default_profile"] = data["default_profile"]
        end
        normalized
      end

      def stringify_keys(value)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, nested), memo|
          memo[key.to_s] = stringify_keys(nested)
        end
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, old_value, new_value|
          if old_value.is_a?(Hash) && new_value.is_a?(Hash)
            deep_merge(old_value, new_value)
          else
            new_value
          end
        end
      end
    end
  end
end

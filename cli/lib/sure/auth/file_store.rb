# frozen_string_literal: true

require "json"
require "time"

require_relative "../config/atomic_file"
require_relative "../config/paths"
require_relative "../errors"
require_relative "credential"
require_relative "store"

module Sure
  module Auth
    # Plaintext fallback for hosts without a usable OS keychain. The file is
    # JSON, 0600, inside the 0700 config directory, and every mutation happens
    # under an exclusive flock followed by an atomic rename. Reads refuse
    # symlinked or group/world-readable files instead of trusting them.
    class FileStore < Store
      SCHEMA_VERSION = 1

      def initialize(paths: Config::Paths.new, path: nil, lock_path: nil)
        @paths = paths
        @path = path || paths.credentials_file
        @lock_path = lock_path || paths.lock_file
      end

      attr_reader :paths, :path, :lock_path

      def read(key)
        return nil unless File.exist?(path)

        check_safety!
        document = load_document(path)
        entry = document["credentials"][key.account]
        return nil if entry.nil?

        credential_from(entry)
      end

      def write(key, credential)
        paths.ensure_directory!
        with_lock do
          document = File.exist?(path) ? load_document(path) : empty_document
          document["credentials"][key.account] = serialize(credential)
          Config::AtomicFile.write(path, JSON.generate(document))
        end
        credential
      end

      # Returns true when a credential was removed.
      def delete(key)
        return false unless File.exist?(path)

        with_lock do
          document = File.exist?(path) ? load_document(path) : empty_document
          removed = !document["credentials"].delete(key.account).nil?
          if document["credentials"].empty?
            File.unlink(path) if File.exist?(path)
          else
            Config::AtomicFile.write(path, JSON.generate(document))
          end
          removed
        end
      end

      # Removes every entry for a profile when the server URL is unknown (for
      # example, `auth logout` after a hand-edited config).
      def delete_profile(profile_name)
        return 0 unless File.exist?(path)

        prefix = "#{profile_name}@"
        with_lock do
          document = File.exist?(path) ? load_document(path) : empty_document
          keys = document["credentials"].keys.select { |key| key.start_with?(prefix) }
          keys.each { |key| document["credentials"].delete(key) }
          if document["credentials"].empty?
            File.unlink(path) if File.exist?(path)
          elsif keys.any?
            Config::AtomicFile.write(path, JSON.generate(document))
          end
          keys.length
        end
      end

      def mode
        :file
      end

      def location
        path
      end

      def inspect
        "#<Sure::Auth::FileStore path=#{path.inspect}>"
      end

      private

      def with_lock
        reject_symlinked_lock!
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
        raise Errors::UsageError, "cannot lock credential file #{lock_path}: #{e.message}"
      end

      def reject_symlinked_lock!
        return unless File.symlink?(lock_path)

        raise Errors::UsageError, "credential lock #{lock_path} must not be a symlink"
      end

      def check_safety!
        raise Errors::UsageError, "credentials file #{path} must not be a symlink" if File.symlink?(path)

        stat = File.stat(path)
        return if Gem.win_platform?

        if (stat.mode & 0o077) != 0
          raise Errors::UsageError,
                "credentials file #{path} is group/world accessible; run `chmod 600 #{path}`"
        end
        return if stat.uid == Process.euid

        raise Errors::UsageError,
              "credentials file #{path} is not owned by the current user; run `chmod 600 #{path}`"
      end

      def load_document(file)
        data = JSON.parse(File.read(file))
        unless data.is_a?(Hash) && data["credentials"].is_a?(Hash)
          raise Errors::UsageError, "credentials file #{path} is not a valid credential document"
        end
        unless data["schema_version"] == SCHEMA_VERSION
          raise Errors::UsageError,
                "credentials file #{path} must set schema_version: #{SCHEMA_VERSION}"
        end

        data
      rescue JSON::ParserError => e
        raise Errors::UsageError, "credentials file #{path} is not valid JSON: #{e.message}"
      end

      def empty_document
        { "schema_version" => SCHEMA_VERSION, "credentials" => {} }
      end

      def serialize(credential)
        {
          "kind" => credential.kind.to_s,
          "secret" => credential.secret,
          "server_url" => credential.server_url,
          "created_at" => serialize_time(credential.created_at)
        }
      end

      def serialize_time(value)
        return nil if value.nil?
        return value.utc.iso8601 if value.respond_to?(:utc) && value.respond_to?(:iso8601)

        value.to_s
      end

      def credential_from(entry)
        Credential.new(
          kind: entry["kind"].to_s.to_sym,
          secret: entry["secret"].to_s,
          server_url: entry["server_url"],
          created_at: parse_time(entry["created_at"])
        )
      end

      def parse_time(value)
        return nil if value.nil? || value.to_s.empty?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        value
      end
    end
  end
end

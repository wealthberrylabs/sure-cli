# frozen_string_literal: true

require "securerandom"

require_relative "../errors"

module Sure
  module Config
    # Crash-safe, private file writes. A temp file in the destination directory
    # plus rename means readers never observe a partial config; chmod and fsync
    # mean the bytes and permissions hit disk before the write is acknowledged.
    module AtomicFile
      module_function

      def write(path, content, mode: 0o600)
        reject_unsafe_target!(path)

        directory = File.dirname(path)
        temp = temp_path(path)
        begin
          File.open(temp, File::WRONLY | File::CREAT | File::EXCL, mode) do |file|
            file.chmod(mode)
            file.write(content)
            file.flush
            file.fsync
          end
          File.rename(temp, path)
          fsync_directory(directory)
        ensure
          File.unlink(temp) if File.exist?(temp)
        end
        path
      end

      def temp_path(path)
        File.join(
          File.dirname(path),
          ".#{File.basename(path)}.tmp-#{Process.pid}-#{SecureRandom.hex(6)}"
        )
      end

      def fsync_directory(directory)
        File.open(directory, File::RDONLY) { |dir| dir.fsync }
      rescue Errno::EINVAL, Errno::EACCES, Errno::EBADF, Errno::EPERM, NotImplementedError
        nil
      end

      def reject_unsafe_target!(path)
        raise Errors::UsageError, "#{path} must not be a symlink" if File.symlink?(path)
        raise Errors::UsageError, "#{path} is a directory" if File.directory?(path)
      end
    end
  end
end

# frozen_string_literal: true

require "open3"
require "timeout"

require_relative "store"

module Sure
  module Auth
    # Runs a keychain helper as a child process with a minimal, scrubbed
    # environment. The secret is only ever written to the child's stdin; it is
    # never an argv element, an environment variable, or part of a shell string.
    class CommandRunner
      DEFAULT_TIMEOUT = 2
      PRESERVED_ENV = %w[
        PATH HOME USER LOGNAME TMPDIR DBUS_SESSION_BUS_ADDRESS
      ].freeze

      Result = Data.define(:stdout, :stderr, :status) do
        def success?
          return status.success? if status.respond_to?(:success?)

          status.to_i.zero?
        end
      end

      def initialize(env: ENV, timeout: DEFAULT_TIMEOUT)
        @env = env
        @timeout = timeout
      end

      attr_reader :env, :timeout

      def run(command, *arguments, stdin_data: nil)
        executable = resolve(command)
        options = stdin_data.nil? ? {} : { stdin_data: stdin_data.to_s }

        stdout, stderr, status = Timeout.timeout(timeout) do
          Open3.capture3(child_environment, executable, *arguments, **options)
        end

        Result.new(stdout: stdout.to_s, stderr: stderr.to_s, status: status)
      rescue Timeout::Error
        raise StoreError, "#{command} did not finish within #{timeout} seconds"
      rescue Errno::ENOENT
        raise StoreError, "#{command} is not installed or not on PATH"
      rescue SystemCallError => e
        raise StoreError, "cannot run #{command}: #{e.message}"
      end

      # Absolute path resolved from PATH, never a shell lookup. Also used by a
      # store to decide whether its helper is available before trying it.
      def resolve(command)
        name = command.to_s
        return name if name.include?(File::SEPARATOR) && File.executable?(name)

        executable = env["PATH"].to_s.split(File::PATH_SEPARATOR).filter_map do |directory|
          next if directory.empty?

          candidate = File.join(directory, name)
          candidate if File.file?(candidate) && File.executable?(candidate)
        end.first
        return executable if executable

        raise StoreError, "#{name} is not installed or not on PATH"
      end

      # Only the variables a helper needs. SURE_API_KEY, SURE_TOKEN, and any
      # Authorization value are structurally impossible to inherit.
      def child_environment
        PRESERVED_ENV.each_with_object({}) do |name, result|
          value = env[name]
          result[name] = value if value
        end
      end

      def inspect
        "#<Sure::Auth::CommandRunner timeout=#{timeout}>"
      end
    end
  end
end

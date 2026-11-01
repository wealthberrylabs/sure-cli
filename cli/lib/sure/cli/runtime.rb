# frozen_string_literal: true

require_relative "../errors"

module Sure
  module CLI
    # Immutable process inputs. Tests inject StringIO streams, a fake clock, and
    # an isolated environment instead of touching real STDIN/STDOUT/ENV.
    class Runtime
      THREAD_KEY = :sure_cli_runtime

      attr_reader :stdin, :stdout, :stderr, :env, :cwd, :clock

      def initialize(stdin:, stdout:, stderr:, env:, cwd:, clock:)
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @env = env
        @cwd = cwd
        @clock = clock
        freeze
      end

      class << self
        def build(stdin: $stdin, stdout: $stdout, stderr: $stderr, env: ENV, cwd: Dir.pwd, clock: Time)
          new(stdin: stdin, stdout: stdout, stderr: stderr, env: env, cwd: cwd, clock: clock)
        end

        def with(runtime)
          previous = Thread.current[THREAD_KEY]
          Thread.current[THREAD_KEY] = runtime
          yield runtime
        ensure
          Thread.current[THREAD_KEY] = previous
        end

        def current
          Thread.current[THREAD_KEY] ||
            raise(Errors::GeneralError, "CLI runtime is not initialized")
        end
      end
    end
  end
end

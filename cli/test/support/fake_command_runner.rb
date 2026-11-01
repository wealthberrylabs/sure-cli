# frozen_string_literal: true

require "sure"

# Records helper invocations and returns scripted results. Used to prove the
# secret travels only on stdin and to simulate missing or failing helpers.
class FakeCommandRunner
  Call = Data.define(:command, :arguments, :stdin_data)

  Status = Struct.new(:exitstatus) do
    def success?
      exitstatus.to_i.zero?
    end
  end

  Response = Data.define(:stdout, :stderr, :success) do
    def status
      Status.new(success ? 0 : 1)
    end
  end

  attr_reader :calls

  def initialize
    @calls = []
    @responses = Hash.new { |hash, key| hash[key] = [] }
  end

  def enqueue(command, stdout: "", stderr: "", success: true)
    @responses[command.to_s] << Response.new(stdout: stdout, stderr: stderr, success: success)
    self
  end

  def run(command, *arguments, stdin_data: nil)
    calls << Call.new(command: command.to_s, arguments: arguments, stdin_data: stdin_data)
    response = @responses[command.to_s].shift || Response.new(stdout: "", stderr: "", success: true)
    Sure::Auth::CommandRunner::Result.new(
      stdout: response.stdout,
      stderr: response.stderr,
      status: response.status
    )
  end

  def resolve(command)
    "/usr/bin/#{command}"
  end
end

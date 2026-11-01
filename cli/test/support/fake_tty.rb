# frozen_string_literal: true

require "stringio"

# Minimal stand-ins for terminals and pipes. Injected through Runtime so no test
# touches the real STDIN/STDOUT.
class FakeTTY
  def initialize(input = "", tty: true)
    @input = input.is_a?(String) ? StringIO.new(input) : input
    @output = StringIO.new
    @tty = tty
  end

  def tty?
    @tty
  end
  alias_method :isatty, :tty?

  def gets(*args)
    @input.gets(*args)
  end

  def read(*args)
    @input.read(*args)
  end

  def each_line(&block)
    @input.each_line(&block)
  end

  def write(data)
    @output.write(data.to_s)
  end

  def print(*args)
    @output.print(*args)
  end

  def puts(*args)
    @output.puts(*args)
  end

  def flush
    @output.flush
    self
  end

  def string
    @output.string
  end

  def rewind
    @output.rewind
    self
  end
end

# A pipe is the same object with tty? false; named for readable tests.
class FakePipe < FakeTTY
  def initialize(input = "")
    super(input, tty: false)
  end
end

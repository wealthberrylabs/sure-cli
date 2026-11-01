# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"
require_relative "../../support/local_http_server"
require_relative "../../support/fake_keychain"
require_relative "../../support/fake_store"

begin
  require "pty"
rescue LoadError
  nil
end

class LoginTest < Minitest::Test
  include TempConfig

  SECRET = "sk_login_secret"

  def setup
    WebMock.allow_net_connect!
  end

  def teardown
    WebMock.disable_net_connect!
  end

  def test_stdin_input_validates_then_stores_one_credential_and_updates_config
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      runtime = build_runtime(env: env, stdin: StringIO.new(SECRET))

      result = Sure::Auth::Login.new(
        runtime: runtime, options: { server: server.url, api_key_stdin: true }
      ).call

      assert_equal "default", result.data["profile"]
      assert_equal server.url, result.data["server_url"]
      assert_equal "file", result.data["credential_source"]
      assert_equal [ "read" ], result.data["scopes"]

      config = YAML.safe_load_file(File.join(xdg, "sure", "config.yml"))
      profile = config.fetch("profiles").fetch("default")
      assert_equal server.url, profile["server_url"]
      assert_equal [ "read" ], profile["scopes"]
      assert_equal "file", profile["credential_store"]
      assert_equal true, profile["read_only"]
      assert_equal true, profile["plaintext_warning_shown"]
      assert_equal 1, server.received.length
      assert_equal "/api/v1/usage", server.received.first.path

      credentials = JSON.parse(File.read(File.join(xdg, "sure", "credentials.json")))
      assert_equal 1, credentials["credentials"].length
      assert_equal [ SECRET ], credentials["credentials"].values.map { |entry| entry["secret"] }
    ensure
      server&.stop
    end
  end

  def test_a_rejected_key_exits_three_and_persists_nothing
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [
        response('{"error":"unauthorized","message":"bad key"}', status: 401)
      ])
      runtime = build_runtime(env: env, stdin: StringIO.new(SECRET))

      error = assert_raises(Sure::Errors::AuthenticationError) do
        Sure::Auth::Login.new(runtime: runtime, options: { server: server.url, api_key_stdin: true }).call
      end

      assert_equal Sure::Errors::ExitCodes::AUTHENTICATION, error.exit_code
      refute File.exist?(File.join(xdg, "sure", "credentials.json"))
      refute File.exist?(File.join(xdg, "sure", "config.yml"))
    ensure
      server&.stop
    end
  end

  def test_the_input_flags_are_mutually_exclusive
    with_temp_config_home do |env, _home, _xdg|
      runtime = build_runtime(env: env)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Auth::Login.new(
          runtime: runtime,
          options: { server: "https://sure.example.com", api_key_file: "key.txt", api_key_stdin: true }
        ).call
      end

      assert_includes error.message, "mutually exclusive"
    end
  end

  def test_api_key_file_dash_is_rejected_in_favor_of_stdin
    with_temp_config_home do |env, _home, _xdg|
      runtime = build_runtime(env: env)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Auth::Login.new(
          runtime: runtime,
          options: { server: "https://sure.example.com", api_key_file: "-" }
        ).call
      end

      assert_includes error.message, "--api-key-stdin"
    end
  end

  def test_non_tty_without_input_never_prompts
    with_temp_config_home do |env, _home, _xdg|
      runtime = build_runtime(env: env, stdin: StringIO.new)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Auth::Login.new(
          runtime: runtime, options: { server: "https://sure.example.com" }
        ).call
      end

      assert_includes error.message, "--api-key-file"
      assert_includes error.message, "--api-key-stdin"
      assert_includes error.message, "SURE_API_KEY"
      assert_equal "", runtime.stderr.string
    end
  end

  def test_hidden_prompt_reads_through_the_injected_stdin_without_echo
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      stdin = FakeTTY.new("#{SECRET}\n")
      runtime = build_runtime(env: env, stdin: stdin)
      file_store = FakeStore.new
      factory = build_factory(server.url, file_store: file_store)

      result = Sure::Auth::Login.new(
        runtime: runtime,
        options: { server: server.url },
        store_factory: factory
      ).call

      assert_equal "file", result.data["credential_source"]
      assert_equal "API key: ", runtime.stderr.string
      assert_equal 1, file_store.writes.length
      refute_includes runtime.stderr.string, SECRET
      refute_includes runtime.stdout.string, SECRET
    ensure
      server&.stop
    end
  end

  def test_a_tty_without_hidden_input_refuses_to_read_a_secret
    with_temp_config_home do |env, _home, _xdg|
      stdin = OpaqueTTY.new
      runtime = build_runtime(env: env, stdin: stdin)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Auth::Login.new(
          runtime: runtime, options: { server: "https://sure.example.com" }
        ).call
      end

      assert_includes error.message, "cannot read a hidden API key"
      assert_includes error.message, "--api-key-file"
      assert_equal 0, stdin.gets_calls
      refute_includes runtime.stdout.string, "API key"
    end
  end

  def test_a_three_byte_key_from_stdin_exits_two_without_echoing_it
    with_temp_config_home do |env, _home, xdg|
      runtime = build_runtime(env: env, stdin: StringIO.new("zq7"))

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Auth::Login.new(
          runtime: runtime,
          options: { server: "https://sure.example.com", api_key_stdin: true }
        ).call
      end

      assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
      assert_includes error.message, "at least 4 bytes"
      refute_includes error.message, "zq7"
      refute File.exist?(File.join(xdg, "sure", "config.yml"))
      refute File.exist?(File.join(xdg, "sure", "credentials.json"))
    end
  end

  def test_a_three_byte_key_file_exits_two_without_echoing_it
    with_temp_config_home do |env, home, xdg|
      path = File.join(home, "short.txt")
      File.write(path, "zq7\n")
      File.chmod(0o600, path)
      runtime = build_runtime(env: env)

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Auth::Login.new(
          runtime: runtime,
          options: { server: "https://sure.example.com", api_key_file: path }
        ).call
      end

      assert_equal Sure::Errors::ExitCodes::USAGE, error.exit_code
      assert_includes error.message, "at least 4 bytes"
      refute_includes error.message, "zq7"
      refute File.exist?(File.join(xdg, "sure", "config.yml"))
      refute File.exist?(File.join(xdg, "sure", "credentials.json"))
    end
  end

  def test_a_real_terminal_does_not_echo_the_typed_key
    skip "PTY is unavailable on this platform" unless defined?(PTY)

    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      cli_dir = File.expand_path("../../..", __dir__)
      output = String.new

      PTY.spawn(
        env,
        "ruby", "-I", File.join(cli_dir, "lib"), File.join(cli_dir, "exe", "sure"),
        "auth", "login", "--server", server.url
      ) do |reader, writer, pid|
        begin
          output << read_until(reader, "API key: ")
          writer.write("#{SECRET}\n")
          writer.flush
          output << read_until_eof(reader)
        ensure
          begin
            Process.wait(pid)
          rescue Errno::ECHILD
            nil
          end
        end
      end

      refute_includes output, SECRET
      assert_equal 1, server.received.length
    ensure
      server&.stop
    end
  end

  def test_a_group_readable_key_file_warns_but_is_read
    with_temp_config_home do |env, home, _xdg|
      path = File.join(home, "key.txt")
      File.write(path, "#{SECRET}\n")
      File.chmod(0o644, path)
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      runtime = build_runtime(env: env)

      Sure::Auth::Login.new(
        runtime: runtime, options: { server: server.url, api_key_file: path }
      ).call

      assert_includes runtime.stderr.string, "chmod 600"
    ensure
      server&.stop
    end
  end

  def test_the_file_fallback_warning_is_emitted_once_per_profile
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body), response(usage_body) ])

      first = Sure::Auth::Login.new(
        runtime: build_runtime(env: env, stdin: StringIO.new(SECRET)),
        options: { server: server.url, api_key_stdin: true }
      ).call
      second = Sure::Auth::Login.new(
        runtime: build_runtime(env: env, stdin: StringIO.new(SECRET)),
        options: { server: server.url, api_key_stdin: true }
      ).call

      assert_equal 1, first.meta[:warnings].length
      assert_empty second.meta[:warnings]
    ensure
      server&.stop
    end
  end

  def test_a_config_write_failure_rolls_back_the_credential
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      file_store = FakeStore.new
      factory = build_factory(server.url, file_store: file_store)
      loader = FailingLoader.new

      error = assert_raises(Sure::Errors::GeneralError) do
        Sure::Auth::Login.new(
          runtime: build_runtime(env: env, stdin: StringIO.new(SECRET)),
          options: { server: server.url, api_key_stdin: true },
          loader: loader,
          store_factory: factory
        ).call
      end

      assert_includes error.message, "config write failed"
      assert_equal 1, file_store.writes.length
      assert_equal 1, file_store.deletes.length
    ensure
      server&.stop
    end
  end

  def test_environment_key_is_used_before_the_prompt
    with_temp_config_home do |env, _home, _xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      runtime = build_runtime(env: env.merge("SURE_API_KEY" => SECRET), stdin: FakeTTY.new)

      Sure::Auth::Login.new(runtime: runtime, options: { server: server.url }).call

      assert_equal "", runtime.stderr.string
    ensure
      server&.stop
    end
  end

  def test_a_crlf_terminated_key_is_normalized
    with_temp_config_home do |env, _home, xdg|
      server = LocalHttpServer.new(responses: [ response(usage_body) ])
      runtime = build_runtime(env: env, stdin: StringIO.new("#{SECRET}\r\n"))

      Sure::Auth::Login.new(runtime: runtime, options: { server: server.url, api_key_stdin: true }).call

      credentials = JSON.parse(File.read(File.join(xdg, "sure", "credentials.json")))
      assert_equal [ SECRET ], credentials["credentials"].values.map { |entry| entry["secret"] }
    ensure
      server&.stop
    end
  end

  private

  # A terminal that reports itself as a TTY but offers no hidden-input API.
  # `gets` is instrumented so a regression that falls back to an echoed read
  # fails loudly instead of leaking the key into the test transcript.
  class OpaqueTTY
    attr_reader :gets_calls

    def initialize
      @gets_calls = 0
    end

    def tty?
      true
    end
    alias_method :isatty, :tty?

    def gets(*_args)
      @gets_calls += 1
      raise "gets must never be used to read a secret"
    end
  end

  PTY_READ_TIMEOUT = 10

  def read_until(io, marker)
    buffer = +""
    deadline = monotonic + PTY_READ_TIMEOUT

    until buffer.include?(marker)
      remaining = deadline - monotonic
      break if remaining <= 0
      break unless IO.select([ io ], nil, nil, remaining)

      begin
        buffer << io.readpartial(4096)
      rescue EOFError
        break
      end
    end

    buffer
  end

  def read_until_eof(io)
    buffer = +""
    deadline = monotonic + PTY_READ_TIMEOUT

    loop do
      remaining = deadline - monotonic
      break if remaining <= 0
      break unless IO.select([ io ], nil, nil, remaining)

      begin
        buffer << io.readpartial(4096)
      rescue EOFError, Errno::EIO
        break
      end
    end

    buffer
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  class FailingLoader
    def initialize
      @config = { "schema_version" => 1, "profiles" => {} }
    end

    def load
      @config
    end

    def save(_changes)
      raise Sure::Errors::GeneralError, "config write failed"
    end
  end

  def build_runtime(env:, stdin: StringIO.new)
    Sure::CLI::Runtime.new(
      stdin: stdin,
      stdout: StringIO.new,
      stderr: StringIO.new,
      env: env,
      cwd: Dir.pwd,
      clock: CLITestHelper::FIXED_CLOCK
    )
  end

  def build_factory(server_url, file_store:, keychain: FakeKeychain.new(available: false))
    Sure::Auth::StoreFactory.new(
      profile: Sure::Config::Profile.new(name: "default", server_url: server_url),
      env: {},
      platform: :linux,
      keychain_store: keychain,
      file_store: file_store
    )
  end

  def response(body, status: 200)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body }
  end

  def usage_body(scopes: [ "read" ])
    JSON.generate({
      "api_key" => {
        "name" => "CLI login key",
        "scopes" => scopes,
        "last_used_at" => "2026-10-31T12:00:00Z",
        "created_at" => "2026-10-30T09:00:00Z"
      },
      "rate_limit" => {
        "tier" => "standard",
        "limit" => 100,
        "current_count" => 1,
        "remaining" => 99,
        "reset_in_seconds" => 3600,
        "reset_at" => "2026-10-31T13:00:00Z"
      },
      "user" => {
        "email" => "user@example.com",
        "first_name" => "Ada",
        "last_name" => "Lovelace"
      }
    })
  end
end

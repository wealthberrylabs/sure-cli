# frozen_string_literal: true

require "test_helper"
require "support/fake_store"

class ScopePreflightTest < Minitest::Test
  Response = Struct.new(:body)

  class FakeClient
    attr_reader :calls

    def initialize(scopes: [ "read_write" ])
      @scopes = scopes
      @calls = []
    end

    def get(path)
      calls << path
      Response.new({ "api_key" => { "scopes" => @scopes } })
    end
  end

  class FakeLoader
    attr_reader :saves

    def initialize
      @saves = []
    end

    def save(changes)
      saves << changes
      changes
    end
  end

  Context = Struct.new(:profile, :credential_source, :client, :loader)

  def test_safe_methods_are_a_no_op
    client = FakeClient.new
    context = context_for(profile(read_only: true), source: :file, client: client)

    Sure::Auth::ScopePreflight.new(context).ensure!(method: "GET")
    Sure::Auth::ScopePreflight.new(context).ensure!(method: "HEAD")

    assert_empty client.calls
  end

  def test_a_read_only_profile_fails_before_any_request
    client = FakeClient.new
    context = context_for(profile(read_only: true), source: :file, client: client)

    error = assert_raises(Sure::Errors::InsufficientScopeError) do
      Sure::Auth::ScopePreflight.new(context).ensure!(method: "POST")
    end

    assert_equal Sure::Errors::ExitCodes::AUTHENTICATION, error.exit_code
    assert_includes error.message, "read-only"
    assert_empty client.calls
  end

  def test_cached_read_write_scopes_allow_a_write_without_a_request
    client = FakeClient.new
    context = context_for(
      profile(read_only: false, scopes: [ "read_write" ]), source: :file, client: client
    )

    Sure::Auth::ScopePreflight.new(context).ensure!(method: "POST")

    assert_empty client.calls
  end

  def test_cached_read_only_scopes_block_a_write
    client = FakeClient.new
    context = context_for(
      profile(read_only: false, scopes: [ "read" ]), source: :file, client: client
    )

    error = assert_raises(Sure::Errors::InsufficientScopeError) do
      Sure::Auth::ScopePreflight.new(context).ensure!(method: "PATCH")
    end

    assert_includes error.message, "scopes: read"
    assert_empty client.calls
  end

  def test_environment_keys_always_fetch_scopes_and_persist_nothing
    client = FakeClient.new(scopes: [ "read" ])
    loader = FakeLoader.new
    context = context_for(profile(read_only: false), source: :environment, client: client, loader: loader)
    preflight = Sure::Auth::ScopePreflight.new(context)

    2.times do
      assert_raises(Sure::Errors::InsufficientScopeError) { preflight.ensure!(method: "DELETE") }
    end

    assert_equal [ "/api/v1/usage", "/api/v1/usage" ], client.calls
    assert_empty loader.saves
  end

  def test_stored_credentials_without_cached_scopes_fetch_once_and_persist
    client = FakeClient.new(scopes: [ "read_write" ])
    loader = FakeLoader.new
    context = context_for(profile(read_only: false, scopes: []), source: :file, client: client, loader: loader)

    Sure::Auth::ScopePreflight.new(context).ensure!(method: "POST")

    assert_equal [ "/api/v1/usage" ], client.calls
    assert_equal [ { "profiles" => { "default" => { "scopes" => [ "read_write" ] } } } ], loader.saves
  end

  def test_stored_credentials_with_fetched_read_scopes_are_blocked
    client = FakeClient.new(scopes: [ "read" ])
    context = context_for(profile(read_only: false, scopes: []), source: :file, client: client)

    error = assert_raises(Sure::Errors::InsufficientScopeError) do
      Sure::Auth::ScopePreflight.new(context).ensure!(method: "POST")
    end

    assert_includes error.message, "read_write"
  end

  private

  def context_for(profile, source:, client:, loader: FakeLoader.new)
    Context.new(profile, source, client, loader)
  end

  def profile(read_only:, scopes: [])
    Sure::Config::Profile.new(
      name: "default",
      server_url: "https://sure.example.com",
      read_only: read_only,
      scopes: scopes
    )
  end
end

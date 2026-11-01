# frozen_string_literal: true

require "sure"

# In-memory credential backend used by store, factory, and auth-command tests.
# It can also stand in for a keychain: `available?` is configurable and a
# failure can be injected per operation.
class FakeStore < Sure::Auth::Store
  attr_reader :mode, :location, :reads, :writes, :deletes, :stored
  attr_accessor :available, :fail_read, :fail_write

  def initialize(mode: :file, location: "fake store", available: true,
                 fail_read: nil, fail_write: nil)
    super()
    @mode = mode
    @location = location
    @available = available
    @fail_read = fail_read
    @fail_write = fail_write
    @stored = {}
    @reads = 0
    @writes = []
    @deletes = []
  end

  def available?
    available
  end

  def read(key)
    @reads += 1
    raise Sure::Auth::StoreError, @fail_read if @fail_read

    stored[key.account]
  end

  def write(key, credential)
    raise Sure::Auth::StoreError, @fail_write if @fail_write

    stored[key.account] = credential
    writes << [ key.account, credential ]
    credential
  end

  def delete(key)
    deletes << key.account
    stored.delete(key.account)
    nil
  end
end

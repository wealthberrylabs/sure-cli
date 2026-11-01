# frozen_string_literal: true

require "sure"

# An in-memory stand-in for a platform keychain. `available?` drives the
# StoreFactory auto-detection path.
class FakeKeychain < FakeStore
  def initialize(available: true, fail_read: nil, fail_write: nil)
    super(
      mode: :keychain,
      location: "Fake Keychain",
      available: available,
      fail_read: fail_read,
      fail_write: fail_write
    )
  end
end

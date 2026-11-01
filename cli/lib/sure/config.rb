# frozen_string_literal: true

require_relative "errors"
require_relative "config/paths"
require_relative "config/profile"
require_relative "config/atomic_file"
require_relative "config/loader"
require_relative "config/resolver"

module Sure
  # Non-secret, per-user configuration: named server profiles and the paths
  # that hold them. Secrets live in Sure::Auth, never here.
  module Config
  end
end

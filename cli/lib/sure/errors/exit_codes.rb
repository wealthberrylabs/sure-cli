# frozen_string_literal: true

module Sure
  module Errors
    # Semantic, stable exit codes shared by every command (D-13).
    module ExitCodes
      SUCCESS = 0
      GENERAL = 1
      USAGE = 2
      AUTHENTICATION = 3
      NOT_FOUND = 4
      VALIDATION = 5
      RATE_LIMITED = 6
      PARTIAL_FAILURE = 7
      NETWORK = 8
      TIMEOUT = 9
      INTERRUPTED = 130
    end
  end
end

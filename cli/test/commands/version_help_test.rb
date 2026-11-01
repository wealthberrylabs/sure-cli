# frozen_string_literal: true

require "test_helper"

class VersionHelpTest < Minitest::Test
  def test_version_constant
    assert_equal "0.1.0", Sure::VERSION
  end
end

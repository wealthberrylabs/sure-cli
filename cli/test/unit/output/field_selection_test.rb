# frozen_string_literal: true

require "test_helper"

class FieldSelectionTest < Minitest::Test
  def test_projects_a_hash_and_each_array_element
    selection = Sure::Output::FieldSelection.new("name,balance")

    assert_equal({ "name" => "Checking", "balance" => 10.0 },
                 selection.apply({ "name" => "Checking", "balance" => 10.0, "id" => "x" }))
    assert_equal(
      [ { "name" => "Checking" }, { "name" => "Savings" } ],
      selection.apply([ { "name" => "Checking", "id" => 1 }, { "name" => "Savings", "id" => 2 } ])
    )
  end

  def test_trims_whitespace_and_matches_case_and_labels
    selection = Sure::Output::FieldSelection.new(" Name , balance ")

    assert_equal %w[Name balance], selection.names
    assert selection.include?("name")
    assert selection.include?("Balance")
    assert_equal [ 0, 2 ], selection.indexes(%w[Name Email Balance])
  end

  def test_nested_values_are_projected_by_top_level_key_only
    selection = Sure::Output::FieldSelection.new("nested")

    projected = selection.apply({ "nested" => { "a" => 1 }, "other" => 2 })

    assert_equal({ "nested" => { "a" => 1 } }, projected)
  end

  def test_unknown_field_names_the_field_and_available_names
    selection = Sure::Output::FieldSelection.new("name,bogus")

    error = assert_raises(Sure::Errors::UsageError) do
      selection.validate!(%w[name balance])
    end

    assert_includes error.message, "bogus"
    assert_includes error.message, "balance"
  end

  def test_empty_segments_and_duplicates_are_usage_errors
    assert_raises(Sure::Errors::UsageError) do
      Sure::Output::FieldSelection.new("name,,balance")
    end
    error = assert_raises(Sure::Errors::UsageError) do
      Sure::Output::FieldSelection.new("name,name")
    end
    assert_includes error.message, "more than once"
  end
end

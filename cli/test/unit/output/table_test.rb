# frozen_string_literal: true

require "test_helper"

class TableOutputTest < Minitest::Test
  def test_renders_configured_columns_without_ansi
    io = StringIO.new
    columns = [
      Sure::Output::Column.new(key: "name", label: "Name"),
      Sure::Output::Column.new(
        key: "balance",
        label: "Balance",
        align: :right,
        formatter: ->(value) { format("%.2f", value) }
      )
    ]

    Sure::Output::Table.new(color: false).render(
      Sure::Output::Result.new(
        data: [ [ "Checking", 1250.75 ] ],
        columns: columns
      ),
      io: io
    )

    assert_includes io.string, "Name"
    assert_includes io.string, "Balance"
    assert_includes io.string, "1250.75"
    refute_includes io.string, "\e["
  end

  def test_infers_columns_from_a_collection_envelope
    io = StringIO.new
    data = {
      "accounts" => [ { "name" => "Checking", "balance" => 10.0 } ],
      "pagination" => { "page" => 1, "per_page" => 25, "total_count" => 1, "total_pages" => 1 }
    }

    Sure::Output::Table.new.render(Sure::Output::Result.new(data: data), io: io)

    assert_includes io.string, "Name"
    assert_includes io.string, "Balance"
    assert_includes io.string, "Checking"
  end

  def test_renders_a_single_hash_as_key_value_rows
    io = StringIO.new

    Sure::Output::Table.new.render(
      Sure::Output::Result.new(data: { "status" => "ok", "count" => 2 }),
      io: io
    )

    assert_includes io.string, "Key"
    assert_includes io.string, "Value"
    assert_includes io.string, "Status"
    assert_includes io.string, "ok"
  end

  def test_renders_an_array_of_scalars_as_one_column
    io = StringIO.new

    Sure::Output::Table.new.render(Sure::Output::Result.new(data: %w[alpha beta]), io: io)

    assert_includes io.string, "Value"
    assert_includes io.string, "alpha"
    assert_includes io.string, "beta"
  end

  def test_never_raises_on_arbitrary_json
    io = StringIO.new

    Sure::Output::Table.new.render(
      Sure::Output::Result.new(data: { "nested" => { "a" => [ 1, 2 ] }, "nil" => nil }),
      io: io
    )

    assert_includes io.string, "Nested"
    assert_includes io.string, "Nil"
  end

  def test_prints_the_footer
    io = StringIO.new

    Sure::Output::Table.new.render(
      Sure::Output::Result.new(data: [ [ 1 ] ], footer: "2 rows"),
      io: io
    )

    assert_includes io.string, "2 rows"
  end
end

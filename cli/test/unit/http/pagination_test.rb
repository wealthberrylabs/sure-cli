# frozen_string_literal: true

require "test_helper"

class PaginationTest < Minitest::Test
  def test_normalizes_the_accounts_shape
    payload = JSON.parse(api_fixture("accounts"))

    normalized = Sure::HTTP::Envelope.normalize(payload, collection_key: "accounts")

    assert_equal 2, normalized[:data].length
    assert_equal "Checking", normalized[:data].first["name"]
    assert_equal 1, normalized[:pagination].page
    assert_equal 25, normalized[:pagination].per_page
    assert_equal 2, normalized[:pagination].total_count
    assert_nil normalized[:pagination].next_page
  end

  def test_normalizes_the_imports_shape
    payload = {
      "data" => [ { "id" => 1 } ],
      "meta" => {
        "current_page" => 1,
        "next_page" => 2,
        "prev_page" => nil,
        "total_pages" => 3,
        "total_count" => 51,
        "per_page" => 25
      }
    }

    normalized = Sure::HTTP::Envelope.normalize(payload)

    assert_equal [ { "id" => 1 } ], normalized[:data]
    assert_equal 1, normalized[:pagination].page
    assert_equal 2, normalized[:pagination].next_page
    assert_equal 3, normalized[:pagination].total_pages
  end

  def test_derives_next_page_when_absent
    payload = {
      "data" => [],
      "meta" => { "page" => 2, "per_page" => 25, "total_pages" => 3, "total_count" => 60 }
    }

    normalized = Sure::HTTP::Envelope.normalize(payload)

    assert_equal 3, normalized[:pagination].next_page
  end

  def test_stops_when_the_last_page_is_reached
    payload = {
      "data" => [],
      "meta" => { "current_page" => 3, "total_pages" => 3, "per_page" => 25 }
    }

    normalized = Sure::HTTP::Envelope.normalize(payload)

    refute normalized[:pagination].next_page?
    assert_nil normalized[:pagination].next_page
  end

  def test_returns_nil_pagination_when_the_payload_has_none
    normalized = Sure::HTTP::Envelope.normalize({ "status" => "ok" })

    assert_equal({ "status" => "ok" }, normalized[:data])
    assert_nil normalized[:pagination]
  end

  def test_validates_per_page
    assert_equal 25, Sure::HTTP::Pagination.validate_per_page!(nil)
    assert_equal 100, Sure::HTTP::Pagination.validate_per_page!("100")
    assert_equal 1, Sure::HTTP::Pagination.validate_per_page!("1")

    [ 0, 101, "abc", "", -1 ].each do |value|
      assert_raises(Sure::Errors::UsageError) do
        Sure::HTTP::Pagination.validate_per_page!(value)
      end
    end
  end

  def test_exposes_next_page_and_params
    pagination = Sure::HTTP::Pagination.new(page: 1, per_page: 50, total_pages: 2)

    assert pagination.next_page?
    assert_equal 2, pagination.next_page
    assert_equal({ page: 2, per_page: 50 }, pagination.params_for(2))
    assert_equal 50, pagination.to_h["per_page"]
  end
end

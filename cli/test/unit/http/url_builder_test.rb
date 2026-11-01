# frozen_string_literal: true

require "test_helper"

class UrlBuilderTest < Minitest::Test
  def test_preserves_the_server_path_prefix
    builder = Sure::HTTP::UrlBuilder.new("https://host/sure")

    assert_equal "https://host/sure/api/v1/usage", builder.join("/api/v1/usage")
  end

  def test_normalizes_duplicate_and_trailing_slashes
    builder = Sure::HTTP::UrlBuilder.new("https://host//sure//")

    assert_equal "https://host/sure/api/v1/usage", builder.join("//api//v1//usage")
  end

  def test_appends_a_query_hash
    builder = Sure::HTTP::UrlBuilder.new("https://host/sure")

    assert_equal "https://host/sure/api/v1/usage?page=2&per_page=25",
                 builder.join("/api/v1/usage", query: { page: 2, per_page: 25 })
  end

  def test_origin_strips_the_default_port
    assert_equal "https://host", Sure::HTTP::UrlBuilder.new("https://host:443/sure").origin
    assert_equal "http://host:8080", Sure::HTTP::UrlBuilder.new("http://host:8080/sure").origin
  end

  def test_rejects_userinfo
    assert_raises(Sure::Errors::UsageError) do
      Sure::HTTP::UrlBuilder.new("https://user:pass@host")
    end
  end

  def test_rejects_a_query_string
    assert_raises(Sure::Errors::UsageError) do
      Sure::HTTP::UrlBuilder.new("https://host?x=1")
    end
  end

  def test_rejects_a_fragment
    assert_raises(Sure::Errors::UsageError) do
      Sure::HTTP::UrlBuilder.new("https://host#section")
    end
  end

  def test_rejects_unsupported_schemes
    assert_raises(Sure::Errors::UsageError) do
      Sure::HTTP::UrlBuilder.new("ftp://host")
    end
  end

  def test_rejects_a_missing_host
    assert_raises(Sure::Errors::UsageError) do
      Sure::HTTP::UrlBuilder.new("https:///path")
    end
  end

  def test_rejects_api_prefixes_in_the_base_url
    %w[https://host/api https://host/api/v1 https://host/sure/api/v1].each do |url|
      error = assert_raises(Sure::Errors::UsageError, url) do
        Sure::HTTP::UrlBuilder.new(url)
      end
      assert_includes error.message, "base URL"
    end
  end

  def test_warns_for_non_loopback_http_once
    stderr = StringIO.new

    Sure::HTTP::UrlBuilder.new("http://example.com/sure", stderr: stderr)

    assert_equal 1, stderr.string.lines.length
    assert_includes stderr.string, "plain http"
  end

  def test_allows_loopback_http_without_warning
    stderr = StringIO.new

    %w[http://localhost http://127.0.0.1 http://[::1]].each do |url|
      Sure::HTTP::UrlBuilder.new(url, stderr: stderr)
    end

    assert_empty stderr.string
  end
end

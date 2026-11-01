# frozen_string_literal: true

require "test_helper"

class CredentialKeyTest < Minitest::Test
  def test_account_is_stable_for_the_same_origin_and_profile
    first = key(profile: "default", origin: "https://host/sure")
    second = key(profile: "default", origin: "https://host/sure/")

    assert_equal first.account, second.account
    assert_match(/\Adefault@[0-9a-f]{16}\z/, first.account)
  end

  def test_account_changes_with_scheme_host_and_profile
    https = key(profile: "default", origin: "https://host/sure")
    http = key(profile: "default", origin: "http://host/sure")
    other = key(profile: "default", origin: "https://other/sure")
    profile = key(profile: "staging", origin: "https://host/sure")

    refute_equal https.account, http.account
    refute_equal https.account, other.account
    refute_equal https.account, profile.account
  end

  def test_service_label_and_origin_fingerprint
    value = key(profile: "default", origin: "https://sure.example.com/sure")

    assert_equal "sure-cli", value.service
    assert_equal "Sure CLI: default (sure.example.com)", value.label
    assert_equal 16, value.origin_fingerprint.length
    assert_equal "https://sure.example.com/sure", value.origin
  end

  def test_default_ports_are_ignored
    with_port = key(profile: "p", origin: "https://host:443/sure")
    without_port = key(profile: "p", origin: "https://host/sure")

    assert_equal without_port.account, with_port.account
  end

  def test_two_path_prefixes_on_one_host_never_share_a_credential
    tenant_a = key(profile: "default", origin: "https://host/tenant-a")
    tenant_b = key(profile: "default", origin: "https://host/tenant-b")

    refute_equal tenant_a.account, tenant_b.account
    refute_equal tenant_a.origin_fingerprint, tenant_b.origin_fingerprint
  end

  def test_a_trailing_slash_does_not_change_the_identity
    plain = key(profile: "default", origin: "https://host/sure")
    slashed = key(profile: "default", origin: "https://host/sure/")

    assert_equal plain.origin, slashed.origin
    assert_equal plain.origin_fingerprint, slashed.origin_fingerprint
  end

  def test_the_root_url_and_a_prefixed_url_are_distinct
    root = key(profile: "default", origin: "https://host/")
    prefixed = key(profile: "default", origin: "https://host/sure")

    refute_equal root.account, prefixed.account
    assert_equal "https://host", root.origin
  end

  def test_root_url_accounts_match_the_pre_change_origin_only_value
    [ "https://host", "https://host:8443", "http://host" ].each do |origin|
      value = key(profile: "default", origin: origin)
      expected = Digest::SHA256.hexdigest(origin)[0, 16]

      assert_equal origin, value.origin
      assert_equal "default@#{expected}", value.account
    end
  end

  def test_inspect_never_includes_a_secret
    value = key(profile: "default", origin: "https://host/tenant-a")

    assert_includes value.inspect, "default@"
    refute_includes value.inspect, "https://"
    refute_includes value.inspect, "tenant-a"
  end

  private

  def key(profile:, origin:)
    Sure::Auth::CredentialKey.new(profile: profile, origin: origin)
  end
end

# frozen_string_literal: true

require "digest"
require "uri"

module Sure
  module Auth
    # Stable identity for a stored credential, scoped to the scheme, host, port,
    # and path prefix the profile targets. The fingerprint keeps credentials for
    # two servers — including two tenants mounted on one origin — from
    # overwriting each other while never putting the server URL or the secret in
    # a keychain account name.
    class CredentialKey
      SERVICE = "sure-cli"

      def initialize(profile:, origin:)
        @profile = profile.to_s
        @origin = normalize_origin(origin)
        @origin_fingerprint = Digest::SHA256.hexdigest(@origin)[0, 16]
        freeze
      end

      attr_reader :profile, :origin, :origin_fingerprint

      def service
        SERVICE
      end

      def account
        "#{profile}@#{origin_fingerprint}"
      end

      def label
        host = URI.parse(origin).host || origin
        "Sure CLI: #{profile} (#{host})"
      rescue URI::InvalidURIError
        "Sure CLI: #{profile}"
      end

      def inspect
        "#<Sure::Auth::CredentialKey profile=#{profile.inspect} account=#{account.inspect}>"
      end

      private

      # The path prefix is part of the identity: `https://host/tenant-a` and
      # `https://host/tenant-b` are different deployments. A trailing slash is
      # not, so `/sure` and `/sure/` name the same credential.
      def normalize_origin(value)
        uri = URI.parse(value.to_s)
        scheme = uri.scheme.to_s.downcase
        host = uri.host.to_s.downcase
        port = uri.port
        default_port = scheme == "https" ? 443 : 80
        port_suffix = port.nil? || port == default_port ? "" : ":#{port}"
        prefix = uri.path.to_s.sub(%r{/+\z}, "")
        "#{scheme}://#{host}#{port_suffix}#{prefix}"
      rescue URI::InvalidURIError
        value.to_s
      end
    end
  end
end

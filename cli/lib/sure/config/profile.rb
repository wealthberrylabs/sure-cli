# frozen_string_literal: true

module Sure
  module Config
    # One fully resolved, non-secret view of a profile. Resolution (flags,
    # environment, file, defaults) happens in Config::Resolver; consumers only
    # ever see this immutable value.
    Profile = Data.define(
      :name,
      :server_url,
      :ca_bundle,
      :tls_verify,
      :open_timeout,
      :read_timeout,
      :output,
      :read_only,
      :credential_store,
      :scopes,
      :plaintext_warning_shown,
      :sources
    ) do
      def initialize(
        name: nil,
        server_url: nil,
        ca_bundle: nil,
        tls_verify: true,
        open_timeout: 5,
        read_timeout: 30,
        output: nil,
        read_only: false,
        credential_store: nil,
        scopes: [],
        plaintext_warning_shown: false,
        sources: {}
      )
        super(
          name: name,
          server_url: server_url,
          ca_bundle: ca_bundle,
          tls_verify: tls_verify,
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          output: output,
          read_only: read_only,
          credential_store: credential_store,
          scopes: Array(scopes).map(&:to_s).freeze,
          plaintext_warning_shown: plaintext_warning_shown,
          sources: sources.freeze
        )
      end

      # Never render anything that could carry a secret. Profiles are non-secret
      # today, but source maps and future fields must not surprise callers.
      def inspect
        "#<Sure::Config::Profile name=#{name.inspect} server_url=#{server_url.inspect} " \
          "ca_bundle=#{ca_bundle.inspect} tls_verify=#{tls_verify.inspect} " \
          "output=#{output.inspect} read_only=#{read_only.inspect} " \
          "credential_store=#{credential_store.inspect} sources=#{sources.inspect}>"
      end

      alias_method :to_s, :inspect
    end
  end
end

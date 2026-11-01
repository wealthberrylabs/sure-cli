# frozen_string_literal: true

require_relative "../config"
require_relative "../errors"
require_relative "../output/result"
require_relative "credential_key"
require_relative "store_factory"

module Sure
  module Auth
    # Deletes the local credential and says plainly that the server-side key
    # must still be revoked in Sure Settings → API Keys. Idempotent: running it
    # again exits 0 with deleted: false.
    class Logout
      ENV_KEY = "SURE_API_KEY"

      def initialize(runtime:, options: {}, loader: nil, store_factory: nil)
        @runtime = runtime
        @options = options || {}
        @paths = Config::Paths.new(env: runtime.env)
        @loader = loader || Config::Loader.new(paths: @paths)
        @store_factory = store_factory
      end

      attr_reader :runtime, :options, :loader

      def call
        name = profile_name
        attributes = stored_attributes(name)
        origin = resolve_origin(attributes)
        store = store_for(name, origin, attributes)

        deleted = if origin
          key = CredentialKey.new(profile: name, origin: origin)
          existed = credential_present?(store, key)
          store.delete(key)
          existed
        else
          store.delete_profile(name).positive?
        end

        warnings = []
        clear_cached_profile(name, warnings)
        warnings << "#{ENV_KEY} is set in this environment and remains active " \
                    "until you unset it in this shell" if runtime.env[ENV_KEY]

        Output::Result.new(
          data: {
            "profile" => name,
            "server_url" => origin,
            "deleted" => deleted,
            "revoked" => false,
            "revocation_guidance" =>
              "sure auth logout cannot revoke the key on the server; " \
              "revoke it in Sure Settings → API Keys."
          },
          meta: { warnings: warnings }
        )
      end

      private

      def profile_name
        from_flag = option(:profile)
        return from_flag.to_s if present?(from_flag)

        from_env = runtime.env["SURE_PROFILE"]
        return from_env.to_s if present?(from_env)

        from_config = loader.load["default_profile"]
        return from_config.to_s if present?(from_config)

        "default"
      end

      def stored_attributes(name)
        loader.load.fetch("profiles", {}).fetch(name, {})
      end

      def resolve_origin(attributes)
        from_flag = option(:server)
        return from_flag.to_s if present?(from_flag)

        from_env = runtime.env["SURE_SERVER"]
        return from_env.to_s if present?(from_env)

        from_profile = attributes["server_url"]
        return from_profile.to_s if present?(from_profile)

        nil
      end

      def store_for(name, origin, attributes)
        return @store_factory if @store_factory

        profile = Config::Profile.new(
          name: name,
          server_url: origin,
          credential_store: attributes["credential_store"],
          plaintext_warning_shown: attributes.fetch("plaintext_warning_shown", false)
        )
        StoreFactory.new(profile: profile, env: runtime.env)
      end

      # Reads only to report whether something was deleted; the secret is never
      # rendered or stored anywhere.
      def credential_present?(store, key)
        !store.read(key).nil?
      rescue Errors::Error, StoreError
        false
      end

      def clear_cached_profile(name, warnings)
        profiles = loader.load.fetch("profiles", {})
        return unless profiles.key?(name)

        loader.save(
          "profiles" => {
            name => { "scopes" => [], "plaintext_warning_shown" => false }
          }
        )
      rescue Errors::Error, SystemCallError => e
        warnings << "could not clear cached profile data: #{e.message}"
      end

      def option(name)
        return nil unless options.respond_to?(:key?)

        if options.key?(name) && !options[name].nil?
          options[name]
        elsif options.key?(name.to_s)
          options[name.to_s]
        end
      end

      def present?(value)
        value.is_a?(String) && !value.empty?
      end
    end
  end
end

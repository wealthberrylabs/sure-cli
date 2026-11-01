# frozen_string_literal: true

require_relative "../errors"
require_relative "credential"
require_relative "credential_key"
require_relative "store"

module Sure
  module Auth
    # Selects the key for one command. SURE_API_KEY wins for this process only;
    # otherwise the profile's stored credential is read. Nothing is persisted
    # here and no network call is made.
    class ApiKeyProvider
      ENV_KEY = "SURE_API_KEY"
      MIN_BYTES = 4
      MAX_BYTES = 4096

      def initialize(env: ENV, store: NullStore.new)
        @env = env
        @store = store
      end

      attr_reader :store

      # Returns [secret, :environment | :store].
      def fetch(profile)
        key = environment_key
        return [ key, :environment ] unless key.nil?

        credential = store.read(key_for(profile))
        return [ credential.secret, :store ] if credential && valid_stored_secret?(credential.secret)

        if credential
          raise Errors::UsageError,
                "the stored API key for profile `#{profile.name}` is shorter " \
                "than #{MIN_BYTES} bytes; run `sure auth login` again"
        end

        raise Errors::AuthenticationError,
              "no API key for profile `#{profile.name}`; " \
              "run `sure auth login` or set #{ENV_KEY}"
      end

      def inspect
        "#<Sure::Auth::ApiKeyProvider store=#{store.class} api_key=[REDACTED]>"
      end

      private

      def environment_key
        raw = @env[ENV_KEY]
        return nil if raw.nil?

        validate_environment_key!(raw)
      end

      def validate_environment_key!(raw)
        value = raw.to_s
        if value.empty? || value.strip.empty?
          raise Errors::UsageError, "#{ENV_KEY} must not be empty or whitespace"
        end
        if value.bytesize > MAX_BYTES
          raise Errors::UsageError, "#{ENV_KEY} must be at most #{MAX_BYTES} bytes"
        end
        if value.match?(/[\r\n\0]/)
          raise Errors::UsageError, "#{ENV_KEY} must not contain CR, LF, or NUL characters"
        end
        if value.bytesize < MIN_BYTES
          raise Errors::UsageError, "#{ENV_KEY} must be at least #{MIN_BYTES} bytes"
        end

        value
      end

      # A stored credential is rejected, never echoed, when it is too short for
      # the redactor to mask.
      def valid_stored_secret?(secret)
        secret.to_s.bytesize >= MIN_BYTES
      end

      def key_for(profile)
        CredentialKey.new(profile: profile.name, origin: profile.server_url)
      end
    end
  end
end

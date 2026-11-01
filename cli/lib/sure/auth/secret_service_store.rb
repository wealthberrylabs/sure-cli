# frozen_string_literal: true

require_relative "command_runner"
require_relative "credential"
require_relative "store"

module Sure
  module Auth
    # Linux Secret Service backend (`secret-tool`). A running session bus is
    # required; without one the store reports itself unavailable so the factory
    # can use the private file fallback.
    class SecretServiceStore < Store
      COMMAND = "secret-tool"

      def initialize(runner: CommandRunner.new, env: ENV)
        @runner = runner
        @env = env
      end

      attr_reader :runner, :env

      def available?
        return false if env["DBUS_SESSION_BUS_ADDRESS"].to_s.empty?

        runner.resolve(COMMAND)
        true
      rescue StoreError
        false
      end

      def read(key)
        result = runner.run(COMMAND, "lookup", *attributes(key))
        return nil unless result.success?

        secret = strip_one_newline(result.stdout)
        return nil if secret.empty?

        credential_for(key, secret)
      end

      def write(key, credential)
        result = runner.run(
          COMMAND, "store", "--label", key.label, *attributes(key),
          stdin_data: credential.secret
        )
        unless result.success?
          raise StoreError, "secret-tool could not store the credential#{detail(result)}"
        end

        credential
      end

      def delete(key)
        runner.run(COMMAND, "clear", *attributes(key))
        nil
      end

      def mode
        :keychain
      end

      def location
        "Linux Secret Service"
      end

      private

      def attributes(key)
        [ "service", key.service, "profile", key.profile, "origin", key.origin_fingerprint ]
      end

      def credential_for(key, secret)
        Credential.new(
          kind: :api_key,
          secret: secret,
          server_url: key.origin,
          created_at: nil
        )
      end

      def strip_one_newline(value)
        value.to_s.sub(/\r?\n\z/, "")
      end

      def detail(result)
        message = result.stderr.to_s.strip
        message.empty? ? "" : " (#{message})"
      end
    end
  end
end

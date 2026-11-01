# frozen_string_literal: true

require_relative "command_runner"
require_relative "credential"
require_relative "store"

module Sure
  module Auth
    # macOS Keychain backend. The secret is passed on stdin (the valueless `-w`
    # form), then read back and compared because Apple does not document that
    # behavior and it has varied across releases.
    class MacKeychainStore < Store
      COMMAND = "security"

      def initialize(runner: CommandRunner.new)
        @runner = runner
      end

      attr_reader :runner

      def available?
        runner.resolve(COMMAND)
        true
      rescue StoreError
        false
      end

      def read(key)
        result = runner.run(
          COMMAND, "find-generic-password", "-a", key.account, "-s", key.service, "-w"
        )
        return nil unless result.success?

        secret = strip_one_newline(result.stdout)
        return nil if secret.empty?

        credential_for(key, secret)
      end

      def write(key, credential)
        result = runner.run(
          COMMAND, "add-generic-password", "-U", "-a", key.account, "-s", key.service, "-w",
          stdin_data: credential.secret
        )
        unless result.success?
          raise StoreError, "security could not store the credential#{detail(result)}"
        end

        stored = read(key)
        unless stored && stored.secret == credential.secret
          raise StoreError, "the macOS keychain did not return the stored credential"
        end

        credential
      end

      def delete(key)
        runner.run(COMMAND, "delete-generic-password", "-a", key.account, "-s", key.service)
        nil
      end

      def mode
        :keychain
      end

      def location
        "macOS Keychain"
      end

      private

      def credential_for(key, secret)
        Credential.new(
          kind: :api_key,
          secret: secret,
          server_url: key.origin,
          created_at: nil
        )
      end

      # Exactly one trailing newline, never arbitrary whitespace: a key could
      # legitimately end in a space.
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

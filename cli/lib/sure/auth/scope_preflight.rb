# frozen_string_literal: true

require_relative "../errors"

module Sure
  module Auth
    # The only write guard. It runs before a write command dispatches, so a
    # read-only key fails with exit 3 instead of sending a request the server
    # would reject. Cached profile scopes are trusted only for stored
    # credentials; an environment key is re-checked against /usage every time.
    class ScopePreflight
      WRITE_METHODS = %w[POST PUT PATCH DELETE].freeze

      def initialize(context)
        @context = context
      end

      attr_reader :context

      def ensure!(method:)
        return unless write?(method)

        profile = context.profile
        if profile.read_only
          raise Errors::InsufficientScopeError,
                "profile `#{profile.name}` is marked read-only; writes require a " \
                "read_write API key. Create one in Sure Settings → API Keys and log in again."
        end

        scopes = scopes_for(profile)
        return if scopes.include?("read_write")

        raise Errors::InsufficientScopeError,
              "this profile's API key is read-only (scopes: #{scopes.join(', ')}); " \
              "writes require read_write. Create a read_write key in " \
              "Sure Settings → API Keys and log in again."
      end

      private

      def write?(method)
        WRITE_METHODS.include?(method.to_s.strip.upcase)
      end

      def scopes_for(profile)
        return fetch_scopes if context.credential_source == :environment

        cached = Array(profile.scopes).map(&:to_s)
        return cached unless cached.empty?

        scopes = fetch_scopes
        persist_scopes(profile, scopes)
        scopes
      end

      def fetch_scopes
        response = context.client.get("/api/v1/usage")
        body = response.body.is_a?(Hash) ? response.body : {}
        Array(body.dig("api_key", "scopes")).map(&:to_s)
      end

      # Best effort: a failed cache write must not block a valid write.
      def persist_scopes(profile, scopes)
        context.loader.save("profiles" => { profile.name => { "scopes" => scopes } })
      rescue Errors::Error, SystemCallError
        nil
      end
    end
  end
end

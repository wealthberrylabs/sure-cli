# frozen_string_literal: true

require_relative "../output/result"

module Sure
  module Auth
    # Renders a non-secret projection of GET /api/v1/usage. It never reads the
    # stored secret for display and never substitutes the profile name for a
    # user the server did not return.
    class Status
      USER_FIELDS = %w[email first_name last_name].freeze
      API_KEY_FIELDS = %w[name scopes last_used_at created_at].freeze
      RATE_LIMIT_FIELDS = %w[tier limit remaining reset_in_seconds].freeze

      def initialize(context:)
        @context = context
      end

      attr_reader :context

      def call
        profile = context.profile
        body = response_body
        warnings = []

        user = project_user(body["user"])
        if user.nil?
          warnings << "the server did not return a user object; " \
                      "an older Sure server may not expose identity on /usage"
        end

        Output::Result.new(
          data: {
            "profile" => profile.name,
            "server_url" => profile.server_url,
            "user" => user,
            "authentication_method" => "api_key",
            "credential_source" => context.credential_source.to_s,
            "api_key" => project_api_key(body["api_key"]),
            "rate_limit" => project_rate_limit(body["rate_limit"])
          },
          meta: { warnings: warnings }
        )
      end

      private

      def response_body
        body = context.client.get("/api/v1/usage").body
        body.is_a?(Hash) ? body : {}
      end

      def project_user(user)
        return nil unless user.is_a?(Hash)

        USER_FIELDS.each_with_object({}) { |field, result| result[field] = user[field] }
      end

      def project_api_key(api_key)
        source = api_key.is_a?(Hash) ? api_key : {}
        {
          "name" => source["name"],
          "scopes" => Array(source["scopes"]).map(&:to_s),
          "last_used_at" => source["last_used_at"],
          "created_at" => source["created_at"]
        }
      end

      def project_rate_limit(rate_limit)
        source = rate_limit.is_a?(Hash) ? rate_limit : {}
        RATE_LIMIT_FIELDS.each_with_object({}) { |field, result| result[field] = source[field] }
      end
    end
  end
end

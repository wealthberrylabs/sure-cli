# frozen_string_literal: true

module Sure
  # Masks credentials wherever text can leave the process: server messages,
  # exception text, verbose lines, dry-run output, and `sure api --raw` bodies.
  # The active credential is registered as soon as it is resolved so even a
  # non-standard key shape cannot leak.
  class Redactor
    REDACTED = "[REDACTED]"

    SENSITIVE_HEADERS = %w[authorization x-api-key proxy-authorization].freeze

    # Shorter values are too likely to appear coincidentally in ordinary text;
    # real keys are 64 hex characters and are caught by HEX_KEY. Every input
    # boundary (env, file, stdin, prompt, store) rejects secrets below this
    # length, so an accepted credential is always maskable.
    MIN_ACTIVE_SECRET_LENGTH = 4

    SENSITIVE_HEADER_PATTERN =
      /\b(authorization|x-api-key|proxy-authorization)\b(\s*[:=]\s*)(?:Bearer\s+)?([^\s"',;}]+)/i
    BEARER_PATTERN = /\b(Bearer)(\s+)([A-Za-z0-9._~+\/=-]+)/i
    SENSITIVE_KEY_PATTERN =
      /("?(?:api_key|apikey|access_token|refresh_token|client_secret|password|secret)"?\s*[:=]\s*)("?)([^"\s,}&]+)/i
    QUERY_PARAMETER_PATTERN = /([?&](?:api_key|access_token|token|secret)=)([^&\s]+)/i
    HEX_KEY_PATTERN = /\b[0-9a-f]{64}\b/i

    def self.sensitive_header?(name)
      SENSITIVE_HEADERS.include?(name.to_s.downcase)
    end

    def initialize(active_secret: nil)
      @active_secret = ""
      register(active_secret)
    end

    attr_reader :active_secret

    # Records the credential currently in use. Registration never exposes or
    # overwrites an already-registered secret.
    def register(secret)
      value = secret.to_s
      if @active_secret.empty? && value.length >= MIN_ACTIVE_SECRET_LENGTH
        @active_secret = value.dup.freeze
      end
      self
    end

    def registered?
      !@active_secret.empty?
    end

    def redact_headers(headers)
      return {} if headers.nil?

      headers.each_with_object({}) do |(key, value), result|
        result[key] = self.class.sensitive_header?(key) ? REDACTED : redact_value(value)
      end
    end

    # Returns a new String; never mutates the input.
    def redact_value(value)
      return value unless value.is_a?(String)
      return value if value.empty?

      result = value.dup
      result = result.gsub(@active_secret, REDACTED) unless @active_secret.empty?
      result = result.gsub(BEARER_PATTERN) { "#{::Regexp.last_match(1)}#{::Regexp.last_match(2)}#{REDACTED}" }
      result = result.gsub(SENSITIVE_HEADER_PATTERN) { "#{::Regexp.last_match(1)}#{::Regexp.last_match(2)}#{REDACTED}" }
      result = result.gsub(SENSITIVE_KEY_PATTERN) do
        "#{::Regexp.last_match(1)}#{::Regexp.last_match(2)}#{REDACTED}"
      end
      result = result.gsub(QUERY_PARAMETER_PATTERN) { "#{::Regexp.last_match(1)}#{REDACTED}" }
      result.gsub(HEX_KEY_PATTERN, REDACTED)
    end

    # Copies an environment hash without the variables a child process must
    # never inherit.
    def scrub_env(env)
      env.each_with_object({}) do |(key, value), result|
        next if sensitive_env_key?(key)

        result[key] = value
      end
    end

    def inspect
      "#<Sure::Redactor active_secret=#{registered? ? REDACTED : 'none'}>"
    end

    alias_method :to_s, :inspect

    private

    def sensitive_env_key?(key)
      name = key.to_s
      name.match?(/\ASURE_(?:API_KEY|TOKEN|SECRET)\z/i) ||
        name.match?(/(?:api_key|access_token|refresh_token|token|secret|password)\z/i)
    end
  end
end

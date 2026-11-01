# frozen_string_literal: true

require "json"
require "uri"

require_relative "../context"
require_relative "../runtime"
require_relative "../../auth/scope_preflight"
require_relative "../../errors"
require_relative "../../output/result"

module Sure
  module CLI
    module Commands
      # Raw /api/v1 escape hatch. It is deliberately not a general HTTP client:
      # no custom host, no custom headers, no unconfirmed writes, and every
      # response goes through the same redaction pipeline as every other command.
      class Api
        METHODS = %w[GET HEAD POST PUT PATCH DELETE].freeze
        WRITE_METHODS = %w[POST PUT PATCH DELETE].freeze
        API_ROOT = "/api/v1"
        FORBIDDEN_ENCODINGS = /%(?:2e|2f|5c)/i

        def initialize(runtime:, options: {})
          @runtime = runtime
          @options = options || {}
        end

        attr_reader :runtime, :options

        def call(method, path)
          verb = normalize_method(method)
          api_path = normalize_path(path)
          body = parse_body

          reject_body_for_safe_methods!(verb, body)
          reject_conflicting_output!

          return dry_run(verb, api_path, body) if flag?(:dry_run)

          # Resolve the output format before any side effect: a bad flag must
          # exit 2 instead of sending a write and then failing to render it.
          context.selector.format unless flag?(:raw)

          confirm_write!(verb, api_path) if write?(verb)

          # A read-only key fails after confirmation but before any write
          # request leaves the process (SAFE-06 / T-04-04).
          preflight.ensure!(method: verb) if write?(verb)

          response = client.request(verb, api_path, body: body)
          render(response)
        end

        private

        def context
          @context ||= Context.current(runtime, options: options)
        end

        def client
          @client ||= context.client
        end

        def preflight
          @preflight ||= Sure::Auth::ScopePreflight.new(context)
        end

        def normalize_method(method)
          verb = method.to_s.strip.upcase
          return verb if METHODS.include?(verb)

          raise Errors::UsageError,
                "unsupported HTTP method #{method.to_s.inspect}; " \
                "use one of #{METHODS.join(', ')}"
        end

        # Accepts only a path under /api/v1. Scheme, host, fragments, traversal,
        # and encoded separators are rejected after URI and percent decoding.
        def normalize_path(path)
          raw = path.to_s
          raise Errors::UsageError, "path is required" if raw.strip.empty?
          raise Errors::UsageError, "path must not contain CR, LF, or NUL bytes" if raw.match?(/[\r\n\0]/)

          decoded = decode_twice(raw)
          if raw.match?(FORBIDDEN_ENCODINGS) || decoded.match?(FORBIDDEN_ENCODINGS) || decoded.include?("..")
            raise Errors::UsageError, "path must not contain traversal or encoded separators"
          end

          uri = parse_uri(raw)
          if uri.scheme || uri.host
            raise Errors::UsageError, "path must be relative to the configured server, not an absolute URL"
          end
          raise Errors::UsageError, "path must not include a fragment" if uri.fragment
          raise Errors::UsageError, "path must start with /api/v1" unless within_api?(uri.path)

          canonical = uri.path
          canonical = "#{canonical}?#{uri.query}" if uri.query && !uri.query.empty?
          canonical
        end

        def parse_uri(raw)
          URI.parse(raw)
        rescue URI::InvalidURIError
          raise Errors::UsageError, "path is not a valid URI path"
        end

        def decode_twice(value)
          first = URI::DEFAULT_PARSER.unescape(value)
          URI::DEFAULT_PARSER.unescape(first)
        rescue ArgumentError
          value
        end

        def within_api?(path)
          path == API_ROOT || path.start_with?("#{API_ROOT}/")
        end

        def parse_body
          return nil unless options_provided?(:data)

          raw = option(:data).to_s
          raise Errors::UsageError, "--data must be valid JSON" if raw.strip.empty?

          JSON.parse(raw)
        rescue JSON::ParserError
          raise Errors::UsageError, "--data must be valid JSON"
        end

        def reject_body_for_safe_methods!(verb, body)
          return if body.nil?
          return if write?(verb)

          raise Errors::UsageError, "--data is not allowed with #{verb}"
        end

        def reject_conflicting_output!
          return unless flag?(:raw)

          if flag?(:json) || flag?(:table)
            raise Errors::UsageError, "--raw cannot be combined with --json or --table"
          end
        end

        def dry_run(verb, api_path, body)
          url = client.url_for(api_path)
          runtime.stdout.puts("#{verb} #{url}")
          runtime.stdout.puts(JSON.pretty_generate(body)) unless body.nil?
          nil
        end

        def confirm_write!(verb, api_path)
          return if flag?(:yes)

          unless tty?(runtime.stdin)
            raise Errors::UsageError,
                  "refusing to #{verb} without confirmation; pass --yes when stdin is not a TTY"
          end

          runtime.stderr.print("Proceed with #{verb} #{api_path}? [y/N] ")
          runtime.stderr.flush if runtime.stderr.respond_to?(:flush)
          answer = runtime.stdin.gets

          return if answer && answer.strip.match?(/\A(?:y|yes)\z/i)

          raise Errors::UsageError, "aborted; no request was sent"
        end

        def render(response)
          return render_raw(response) if flag?(:raw)

          context.selector.render(
            Output::Result.new(
              data: response.body,
              meta: {
                http_status: response.status,
                request_id: response.request_id,
                rate_limit: response.rate_limit
              }
            )
          )
        end

        # --raw means "no envelope", never "no redaction".
        def render_raw(response)
          body = client.redactor.redact_value(response.raw_body.to_s)
          runtime.stdout.write(body)
          runtime.stdout.write("\n") unless body.end_with?("\n")
        end

        def write?(verb)
          WRITE_METHODS.include?(verb)
        end

        def flag?(name)
          truthy?(option(name))
        end

        def options_provided?(name)
          options.respond_to?(:key?) && (options.key?(name) || options.key?(name.to_s)) &&
            !option(name).nil?
        end

        def option(name)
          return nil unless options.respond_to?(:key?)

          if options.key?(name) && !options[name].nil?
            options[name]
          elsif options.key?(name.to_s)
            options[name.to_s]
          end
        end

        def truthy?(value)
          value == true || value.to_s.match?(/\A(?:1|true|yes|on)\z/i)
        end

        def tty?(io)
          io.respond_to?(:tty?) && io.tty?
        end
      end
    end
  end
end

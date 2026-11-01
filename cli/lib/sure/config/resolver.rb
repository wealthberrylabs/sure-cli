# frozen_string_literal: true

require_relative "../errors"
require_relative "../http/url_builder"
require_relative "loader"
require_relative "paths"
require_relative "profile"

module Sure
  module Config
    # Resolves one immutable Profile per command. Precedence is always
    # flag > environment > profile file > default, and the source of each value
    # is recorded for diagnostics. Secrets are never read here.
    class Resolver
      TRUE_VALUES = %w[1 true yes on].freeze
      FALSE_VALUES = %w[0 false no off].freeze
      OUTPUTS = %w[table json].freeze
      INSECURE_WARNING =
        "warning: TLS verification is disabled; the connection can be intercepted"

      def initialize(env: ENV, options: {}, loader: Loader.new, cwd: Dir.pwd, stderr: nil)
        @env = env
        @options = options || {}
        @loader = loader
        @cwd = cwd
        @stderr = stderr
      end

      attr_reader :env, :options, :loader

      def resolve(profile_name: nil)
        data = loader.load
        name, name_source = resolve_profile_name(data, profile_name)
        attributes = fetch_profile_attributes(data, name)

        server, server_source = resolve_server(attributes)
        HTTP::UrlBuilder.parse(server)
        ca_bundle, ca_source = resolve_ca_bundle(attributes)
        tls_verify, tls_source = resolve_tls(attributes, ca_bundle)
        output, output_source = resolve_output(attributes)

        Profile.new(
          name: name,
          server_url: server,
          ca_bundle: ca_bundle,
          tls_verify: tls_verify,
          open_timeout: attributes.fetch("open_timeout", 5),
          read_timeout: attributes.fetch("read_timeout", 30),
          output: output,
          read_only: attributes.fetch("read_only", false),
          credential_store: attributes["credential_store"],
          scopes: attributes.fetch("scopes", []),
          plaintext_warning_shown: attributes.fetch("plaintext_warning_shown", false),
          sources: {
            profile: name_source,
            server: server_source,
            ca_bundle: ca_source,
            tls_verify: tls_source,
            output: output_source
          }
        )
      end

      private

      def resolve_profile_name(data, explicit)
        return [ explicit, :flag ] if present?(explicit)
        return [ options[:profile], :flag ] if present?(options[:profile])

        env_profile = env["SURE_PROFILE"]
        return [ env_profile, :environment ] if present?(env_profile)

        default = data["default_profile"]
        return [ default, :profile ] if present?(default)

        [ "default", :default ]
      end

      def fetch_profile_attributes(data, name)
        profiles = data.fetch("profiles", {})
        profiles.fetch(name, {})
      end

      def resolve_server(attributes)
        return [ options[:server].to_s, :flag ] if present?(options[:server])

        env_server = env["SURE_SERVER"]
        return [ env_server.to_s, :environment ] if present?(env_server)

        profile_server = attributes["server_url"]
        return [ profile_server.to_s, :profile ] if present?(profile_server)

        raise Errors::UsageError,
              "no server URL for the selected profile; pass --server or set SURE_SERVER"
      end

      def resolve_ca_bundle(attributes)
        options_ca = options[:ca_bundle]
        return [ expand_ca_bundle(options_ca, cwd_relative: true), :flag ] if present?(options_ca)

        env_ca = env["SURE_CA_BUNDLE"]
        return [ expand_ca_bundle(env_ca, cwd_relative: true), :environment ] if present?(env_ca)

        profile_ca = attributes["ca_bundle"]
        return [ expand_ca_bundle(profile_ca, cwd_relative: false), :profile ] if present?(profile_ca)

        [ nil, :system ]
      end

      def expand_ca_bundle(value, cwd_relative:)
        base = cwd_relative ? @cwd : loader.paths.directory
        expanded = File.expand_path(value, base)
        return expanded if File.file?(expanded) && File.readable?(expanded)

        raise Errors::UsageError, "CA bundle #{expanded} is not readable"
      end

      def resolve_tls(attributes, ca_bundle)
        if truthy?(options[:insecure])
          reject_insecure_with_ca!(ca_bundle)
          warn_insecure
          return [ false, :flag ]
        end

        env_insecure = env["SURE_INSECURE"]
        unless env_insecure.nil?
          insecure = parse_boolean(env_insecure, "SURE_INSECURE")
          warn_insecure if insecure
          return [ !insecure, :environment ]
        end

        profile_verify = attributes["tls_verify"]
        unless profile_verify.nil?
          warn_insecure unless profile_verify
          return [ profile_verify, :profile ]
        end

        [ true, :default ]
      end

      def reject_insecure_with_ca!(ca_bundle)
        return unless ca_bundle && present?(options[:ca_bundle])

        raise Errors::UsageError, "--ca-bundle and --insecure cannot be used together"
      end

      def resolve_output(attributes)
        flags = { json: :json, table: :table, csv: :csv, ndjson: :ndjson }
        flags.each do |option, value|
          return [ value, :flag ] if truthy?(options[option])
        end

        env_output = env["SURE_OUTPUT"]
        unless env_output.nil?
          return [ parse_output(env_output, "SURE_OUTPUT"), :environment ]
        end

        profile_output = attributes["output"]
        if present?(profile_output)
          return [ parse_output(profile_output, "profile output"), :profile ]
        end

        [ nil, :default ]
      end

      def parse_output(value, name)
        normalized = value.to_s.strip.downcase
        return normalized.to_sym if OUTPUTS.include?(normalized)

        raise Errors::UsageError, "#{name} must be one of #{OUTPUTS.join(', ')}"
      end

      def parse_boolean(value, name)
        normalized = value.to_s.strip.downcase
        return true if TRUE_VALUES.include?(normalized)
        return false if FALSE_VALUES.include?(normalized)

        raise Errors::UsageError,
              "#{name} must be one of #{TRUE_VALUES.join('/')} or #{FALSE_VALUES.join('/')}"
      end

      def warn_insecure
        return if @warned_insecure || @stderr.nil?

        @stderr.puts(INSECURE_WARNING)
        @warned_insecure = true
      end

      def truthy?(value)
        value == true || %w[true 1 yes on].include?(value.to_s.strip.downcase)
      end

      def present?(value)
        value.is_a?(String) && !value.empty?
      end
    end
  end
end

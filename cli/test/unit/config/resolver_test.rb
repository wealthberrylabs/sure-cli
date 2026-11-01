# frozen_string_literal: true

require "test_helper"
require_relative "../../support/temp_config"

class ResolverTest < Minitest::Test
  include TempConfig

  INVALID_URL_FIXTURE = File.expand_path("../../fixtures/config/invalid_url.yml", __dir__)

  def test_precedence_table_covers_flag_environment_profile_and_default
    cases = [
      {
        label: "flag",
        default_profile: "work",
        options: { profile: "work", server: "https://flag.example" },
        env: { "SURE_PROFILE" => "environment", "SURE_SERVER" => "https://environment.example" },
        profile: "work",
        profile_source: :flag,
        server: "https://flag.example",
        server_source: :flag
      },
      {
        label: "environment",
        default_profile: "work",
        options: {},
        env: { "SURE_PROFILE" => "work", "SURE_SERVER" => "https://environment.example" },
        profile: "work",
        profile_source: :environment,
        server: "https://environment.example",
        server_source: :environment
      },
      {
        label: "profile",
        default_profile: "work",
        options: {},
        env: {},
        profile: "work",
        profile_source: :profile,
        server: "https://work.example",
        server_source: :profile
      },
      {
        label: "default",
        default_profile: nil,
        options: {},
        env: {},
        profile: "default",
        profile_source: :default,
        server: "https://default.example",
        server_source: :profile
      }
    ]

    cases.each do |test_case|
      with_temp_config_home do |base_env|
        paths = paths_for(base_env)
        write_config(paths, config_for(test_case[:default_profile]))
        resolver = build_resolver(paths, base_env.merge(test_case[:env]), test_case[:options])

        profile = resolver.resolve

        assert_equal test_case[:profile], profile.name, test_case[:label]
        assert_equal test_case[:profile_source], profile.sources[:profile], test_case[:label]
        assert_equal test_case[:server], profile.server_url, test_case[:label]
        assert_equal test_case[:server_source], profile.sources[:server], test_case[:label]
      end
    end
  end

  def test_explicit_profile_name_argument_wins
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for("work"))
      resolver = build_resolver(paths, env, { profile: "default" })

      profile = resolver.resolve(profile_name: "work")

      assert_equal "work", profile.name
      assert_equal :flag, profile.sources[:profile]
    end
  end

  def test_missing_server_names_the_flag_and_environment_variable
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, {
        "schema_version" => 1,
        "profiles" => { "default" => { "tls_verify" => true } }
      })

      error = assert_raises(Sure::Errors::UsageError) do
        build_resolver(paths, env, {}).resolve
      end

      assert_includes error.message, "--server"
      assert_includes error.message, "SURE_SERVER"
    end
  end

  def test_rejects_server_url_with_the_api_prefix
    with_temp_config_home do |env|
      paths = paths_for(env)
      paths.ensure_directory!
      FileUtils.cp(INVALID_URL_FIXTURE, paths.config_file)
      File.chmod(0o600, paths.config_file)

      error = assert_raises(Sure::Errors::UsageError) do
        build_resolver(paths, env, {}).resolve
      end

      assert_includes error.message, "base URL"
      assert_includes error.message, "/api/v1"
    end
  end

  def test_profile_ca_bundle_is_expanded_and_keeps_tls_verification
    with_temp_config_home do |env|
      paths = paths_for(env)
      ca = File.join(paths.directory, "ca.pem")
      write_config(paths, config_for("default").merge(
        "profiles" => { "default" => {
          "server_url" => "https://sure.example.com",
          "ca_bundle" => "ca.pem"
        } }
      ))
      File.write(ca, "PEM")
      File.chmod(0o600, ca)

      profile = build_resolver(paths, env, {}).resolve

      assert_equal ca, profile.ca_bundle
      assert_equal :profile, profile.sources[:ca_bundle]
      assert profile.tls_verify
    end
  end

  def test_relative_ca_bundle_flag_resolves_against_cwd
    with_temp_config_home do |env, home|
      paths = paths_for(env)
      write_config(paths, config_for("default"))
      ca = File.join(home, "ca.pem")
      File.write(ca, "PEM")

      profile = build_resolver(
        paths, env, { ca_bundle: "ca.pem" }, cwd: home
      ).resolve

      assert_equal ca, profile.ca_bundle
      assert_equal :flag, profile.sources[:ca_bundle]
    end
  end

  def test_missing_ca_bundle_names_the_resolved_path
    with_temp_config_home do |env, home|
      paths = paths_for(env)
      write_config(paths, config_for("default"))
      expected = File.join(home, "missing.pem")

      error = assert_raises(Sure::Errors::UsageError) do
        build_resolver(paths, env, { ca_bundle: "missing.pem" }, cwd: home).resolve
      end

      assert_includes error.message, expected
      assert_includes error.message, "not readable"
    end
  end

  def test_insecure_disables_tls_verification_and_warns_once
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for("default"))
      stderr = StringIO.new
      resolver = build_resolver(paths, env, { insecure: true }, stderr: stderr)

      profile = resolver.resolve
      resolver.resolve

      refute profile.tls_verify
      assert_equal :flag, profile.sources[:tls_verify]
      assert_equal 1, stderr.string.lines.length
      assert_includes stderr.string, "TLS verification"
    end
  end

  def test_ca_bundle_and_insecure_together_are_a_usage_error
    with_temp_config_home do |env, home|
      paths = paths_for(env)
      write_config(paths, config_for("default"))
      ca = File.join(home, "ca.pem")
      File.write(ca, "PEM")

      error = assert_raises(Sure::Errors::UsageError) do
        build_resolver(paths, env, { ca_bundle: ca, insecure: true }).resolve
      end

      assert_includes error.message, "--ca-bundle"
      assert_includes error.message, "--insecure"
    end
  end

  def test_rejects_an_invalid_sure_insecure_value
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for("default"))

      error = assert_raises(Sure::Errors::UsageError) do
        build_resolver(paths, env.merge("SURE_INSECURE" => "maybe"), {}).resolve
      end

      assert_includes error.message, "SURE_INSECURE"
    end
  end

  def test_sure_insecure_false_keeps_verification
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for("default"))

      profile = build_resolver(paths, env.merge("SURE_INSECURE" => "off"), {}).resolve

      assert profile.tls_verify
      assert_equal :environment, profile.sources[:tls_verify]
    end
  end

  def test_profile_tls_verify_false_warns
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, {
        "schema_version" => 1,
        "profiles" => { "default" => {
          "server_url" => "https://sure.example.com", "tls_verify" => false
        } }
      })
      stderr = StringIO.new

      profile = build_resolver(paths, env, {}, stderr: stderr).resolve

      refute profile.tls_verify
      assert_equal :profile, profile.sources[:tls_verify]
      assert_includes stderr.string, "TLS verification"
    end
  end

  def test_output_flag_beats_environment_and_profile
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, {
        "schema_version" => 1,
        "profiles" => { "default" => {
          "server_url" => "https://sure.example.com", "output" => "table"
        } }
      })

      profile = build_resolver(
        paths, env.merge("SURE_OUTPUT" => "table"), { json: true }
      ).resolve

      assert_equal :json, profile.output
      assert_equal :flag, profile.sources[:output]
    end
  end

  def test_sure_output_accepts_every_machine_format_and_rejects_yaml
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for("default"))

      %w[json csv ndjson].each do |format|
        profile = build_resolver(paths, env.merge("SURE_OUTPUT" => format), {}).resolve
        assert_equal format.to_sym, profile.output
        assert_equal :environment, profile.sources[:output]
      end

      error = assert_raises(Sure::Errors::UsageError) do
        build_resolver(paths, env.merge("SURE_OUTPUT" => "yaml"), {}).resolve
      end
      assert_includes error.message, "SURE_OUTPUT"
    end
  end

  def test_profile_output_is_used_when_no_flag_or_environment
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, {
        "schema_version" => 1,
        "profiles" => { "default" => {
          "server_url" => "https://sure.example.com", "output" => "table"
        } }
      })

      profile = build_resolver(paths, env, {}).resolve

      assert_equal :table, profile.output
      assert_equal :profile, profile.sources[:output]
    end
  end

  def test_profile_defaults_are_applied
    with_temp_config_home do |env|
      paths = paths_for(env)
      write_config(paths, config_for("default"))

      profile = build_resolver(paths, env, {}).resolve

      assert_equal 5, profile.open_timeout
      assert_equal 30, profile.read_timeout
      refute profile.read_only
      assert_equal [], profile.scopes
      refute profile.plaintext_warning_shown
      assert profile.tls_verify
    end
  end

  private

  def config_for(default_profile)
    data = {
      "schema_version" => 1,
      "profiles" => {
        "default" => { "server_url" => "https://default.example" },
        "work" => { "server_url" => "https://work.example" }
      }
    }
    data["default_profile"] = default_profile if default_profile
    data
  end

  def build_resolver(paths, env, options, cwd: Dir.pwd, stderr: nil)
    Sure::Config::Resolver.new(
      env: env,
      options: options,
      loader: Sure::Config::Loader.new(paths: paths),
      cwd: cwd,
      stderr: stderr
    )
  end
end

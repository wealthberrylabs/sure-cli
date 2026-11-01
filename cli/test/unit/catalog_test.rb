# frozen_string_literal: true

require "test_helper"

class CatalogTest < Minitest::Test
  INVALID_FIXTURE = File.expand_path("../fixtures/config/operations_invalid.yml", __dir__)

  def test_default_catalog_validates_against_the_application
    assert Sure::Catalog::Validator.validate!(Sure::Catalog.default, Sure::CLI::Application)
  end

  def test_auth_subcommand_group_is_accepted_without_its_own_entry
    refute_includes Sure::Catalog.default.ids, "auth"
    assert Sure::Catalog::Validator.validate!(Sure::Catalog.default, Sure::CLI::Application)
  end

  def test_api_entry_exposes_locked_example
    api = Sure::Catalog.fetch("api")

    assert_equal "sure api GET /api/v1/accounts", api.examples.first
    assert api.implemented?
    refute api.planned?
    assert api.frozen?
  end

  def test_auth_login_options_never_offer_a_bare_api_key
    names = Sure::Catalog.fetch("auth.login").options.map(&:name)

    assert_includes names, "api-key-file"
    assert_includes names, "api-key-stdin"
    refute_includes names, "api-key"
  end

  def test_planned_entries_are_marked_planned
    %w[accounts.list transactions.add cashflow balance-sheet budgets reports].each do |id|
      entry = Sure::Catalog.fetch(id)

      assert entry.planned?, "#{id} should be planned"
      refute entry.implemented?, "#{id} should not be implemented"
    end
  end

  def test_planned_entries_do_not_appear_in_help
    output = run_cli("help").stdout

    %w[accounts transactions cashflow balance-sheet budgets reports].each do |word|
      refute_includes output, word
    end
  end

  def test_rejects_implemented_entry_without_a_matching_command
    commands = application_commands.merge("ghost" => entry(%w[ghost]))

    error = assert_raises(Sure::Errors::Error) do
      Sure::Catalog::Validator.validate!(build_catalog(commands), Sure::CLI::Application)
    end

    assert_includes error.message, "ghost"
  end

  def test_rejects_orphan_leaf_command
    commands = application_commands
    commands.delete("doctor")

    error = assert_raises(Sure::Errors::Error) do
      Sure::Catalog::Validator.validate!(build_catalog(commands), Sure::CLI::Application)
    end

    assert_includes error.message, "doctor"
    assert_includes error.message, "no catalog entry"
  end

  def test_rejects_duplicate_paths
    commands = application_commands
    commands["version.duplicate"] = entry(%w[version])

    error = assert_raises(Sure::Errors::Error) do
      Sure::Catalog::Validator.validate!(build_catalog(commands), Sure::CLI::Application)
    end

    assert_includes error.message, "duplicate catalog paths"
  end

  def test_rejects_rm_alias
    commands = application_commands
    commands["version"] = entry(%w[version], aliases: [ "rm" ])

    error = assert_raises(Sure::Errors::Error) do
      Sure::Catalog::Validator.validate!(build_catalog(commands), Sure::CLI::Application)
    end

    assert_includes error.message, "rm alias"
  end

  def test_rejects_destructive_path_that_does_not_end_in_delete
    commands = application_commands
    commands["accounts.remove"] = entry(%w[accounts remove], risk: "destructive")

    error = assert_raises(Sure::Errors::Error) do
      Sure::Catalog::Validator.validate!(build_catalog(commands), Sure::CLI::Application)
    end

    assert_includes error.message, "must end in delete"
  end

  def test_accepts_destructive_path_that_ends_in_delete
    commands = application_commands
    commands["transactions.delete"] =
      entry(%w[transactions delete], risk: "destructive", status: "planned")

    assert Sure::Catalog::Validator.validate!(build_catalog(commands), Sure::CLI::Application)
  end

  def test_rejects_malformed_yaml_root
    error = assert_raises(Sure::Errors::Error) do
      Sure::Catalog::Loader.load(INVALID_FIXTURE)
    end

    assert_includes error.message, INVALID_FIXTURE
    assert_includes error.message, "mapping"
  end

  def test_schema_version_is_one
    assert_equal 1, Sure::Catalog.default.schema_version
  end

  private

  def build_catalog(commands)
    Sure::Catalog.new("schema_version" => 1, "commands" => commands)
  end

  def application_commands
    {
      "version" => entry(%w[version]),
      "help" => entry(%w[help]),
      "auth.login" => entry(%w[auth login]),
      "auth.logout" => entry(%w[auth logout]),
      "auth.status" => entry(%w[auth status]),
      "api" => entry(%w[api]),
      "doctor" => entry(%w[doctor]),
      "completion" => entry(%w[completion])
    }
  end

  def entry(path, **overrides)
    {
      "path" => path,
      "summary" => "summary",
      "description" => "description",
      "risk" => "read",
      "status" => "implemented",
      "aliases" => [],
      "arguments" => [],
      "options" => [],
      "examples" => [ "sure #{path.join(' ')}" ],
      "api" => { "method" => nil, "path" => nil },
      "version_added" => "0.1.0"
    }.merge(overrides.transform_keys(&:to_s))
  end
end

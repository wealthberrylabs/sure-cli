# frozen_string_literal: true

require "test_helper"
require "tempfile"

class CompletionCommandTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/completion", __dir__)

  def test_bash_script_matches_the_snapshot_and_passes_bash_n
    result = run_cli("completion", "bash")

    assert_equal 0, result.status
    assert_equal File.read(File.join(FIXTURES, "sure.bash")), result.stdout
    assert_empty result.stderr
    assert bash_syntax_ok?(result.stdout)
  end

  def test_zsh_script_starts_with_compdef_and_matches_the_snapshot
    result = run_cli("completion", "zsh")

    assert_equal 0, result.status
    assert result.stdout.start_with?("#compdef sure\n")
    assert_equal File.read(File.join(FIXTURES, "_sure")), result.stdout
  end

  def test_fish_script_uses_complete_c_and_matches_the_snapshot
    result = run_cli("completion", "fish")

    assert_equal 0, result.status
    assert_includes result.stdout, "complete -c sure"
    assert_equal File.read(File.join(FIXTURES, "sure.fish")), result.stdout
  end

  def test_every_script_contains_implemented_commands_only
    %w[bash zsh fish].each do |shell|
      result = run_cli("completion", shell)

      assert_equal 0, result.status
      %w[auth api doctor completion].each do |command|
        assert_includes result.stdout, command, "#{shell} is missing #{command}"
      end
      refute_includes result.stdout, "accounts.list"
      refute_includes result.stdout, "transactions.add"
    end
  end

  def test_unsupported_shell_exits_two_and_lists_supported_shells
    result = run_cli("completion", "powershell")

    assert_equal 2, result.status
    assert_includes result.stderr, "bash"
    assert_includes result.stderr, "zsh"
    assert_includes result.stderr, "fish"
  end

  def test_a_malicious_catalog_path_is_rejected_before_any_output
    [ "bad;rm", "bad$(id)", "bad\nrm" ].each do |token|
      catalog = catalog_with(path: [ token ])

      error = assert_raises(Sure::Errors::UsageError) do
        Sure::Completion::Generator.new(catalog: catalog).render("bash")
      end
      assert_includes error.message, "unsafe completion token"
    end
  end

  def test_canonical_names_are_included_even_when_aliases_exist
    catalog = catalog_with(path: [ "transactions" ], aliases: [ "tx" ])

    script = Sure::Completion::Generator.new(catalog: catalog).render("bash")

    assert_includes script, "transactions"
    assert_includes script, "tx"
  end

  private

  def bash_syntax_ok?(script)
    Tempfile.create([ "sure-completion", ".bash" ]) do |file|
      file.write(script)
      file.flush
      system("bash", "-n", file.path, out: File::NULL, err: File::NULL)
    end
  end

  def catalog_with(path:, aliases: [])
    Sure::Catalog.new(
      "schema_version" => 1,
      "commands" => {
        "custom" => {
          "path" => path,
          "summary" => "Custom command",
          "risk" => "read",
          "status" => "implemented",
          "aliases" => aliases
        }
      }
    )
  end
end

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

  def test_zsh_script_guards_its_self_call_and_matches_the_snapshot
    result = run_cli("completion", "zsh")

    assert_equal 0, result.status
    assert result.stdout.start_with?("#compdef sure\n")
    assert_includes result.stdout, %(if [ "$funcstack[1]" = "_sure" ]; then)
    assert_includes result.stdout, "compdef _sure sure"
    refute_match(/^_sure "\$@"$/, result.stdout)
    assert result.stdout.end_with?("fi\n"), "the zsh script must end with the guarded stanza, not a bare call"
    assert_equal File.read(File.join(FIXTURES, "_sure")), result.stdout
  end

  def test_zsh_script_parses_and_sources_cleanly
    skip "zsh is not installed; skipping the zsh syntax and source checks" unless zsh_path

    result = run_cli("completion", "zsh")

    assert_equal 0, result.status

    Tempfile.create([ "sure-completion", ".zsh" ]) do |file|
      file.write(result.stdout)
      file.flush

      assert zsh_syntax_ok?(file.path), "zsh -n rejected the generated completion script"
      assert zsh_sources_cleanly?(file.path), "sourcing the generated completion after compinit failed"
    end
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

  def zsh_path
    return @zsh_path if defined?(@zsh_path)

    @zsh_path = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
                   .map { |dir| File.join(dir, "zsh") }
                   .find { |candidate| File.executable?(candidate) }
  end

  def zsh_syntax_ok?(path)
    system("zsh", "-n", path, out: File::NULL, err: File::NULL)
  end

  # Mirrors the documented direct-source install path: compinit defines compdef,
  # then sourcing the script must register the completion without running it.
  def zsh_sources_cleanly?(path)
    system("zsh", "-f", "-c", 'autoload -Uz compinit; compinit -u; source "$1"',
           "sure-completion-sourced", path, out: File::NULL, err: File::NULL)
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

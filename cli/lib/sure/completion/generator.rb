# frozen_string_literal: true

require_relative "../catalog"
require_relative "../errors"

module Sure
  module Completion
    # Generates a static completion script from implemented catalog entries.
    # Only validated command tokens and fixed option names reach the script, so
    # catalog text can never inject shell code.
    class Generator
      SHELLS = %w[bash zsh fish].freeze
      TOKEN = /\A[a-z0-9][a-z0-9_-]*\z/
      GLOBAL_FLAGS = %w[
        --profile --server --ca-bundle --insecure
        --json --table --csv --ndjson --fields
        --color --no-color --quiet --verbose --help --version
      ].freeze

      def initialize(catalog: Catalog.default)
        @catalog = catalog
      end

      attr_reader :catalog

      def render(shell)
        name = shell.to_s.strip.downcase
        unless SHELLS.include?(name)
          raise Errors::UsageError,
                "unsupported shell #{shell.to_s.inspect}; supported shells: #{SHELLS.join(', ')}"
        end

        send("render_#{name}")
      end

      private

      def render_bash
        root = words(root_commands.keys)
        auth = words(subcommands_for("auth"))

        <<~BASH
          # bash completion for sure
          _sure_completion() {
            local cur
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"

            case "${cur}" in
              -*)
                COMPREPLY=( $(compgen -W "#{words(GLOBAL_FLAGS)}" -- "${cur}") )
                return 0
                ;;
            esac

            if [ "$COMP_CWORD" -eq 1 ]; then
              COMPREPLY=( $(compgen -W "#{root}" -- "${cur}") )
              return 0
            fi

            case "${COMP_WORDS[1]}" in
              auth)
                if [ "$COMP_CWORD" -eq 2 ]; then
                  COMPREPLY=( $(compgen -W "#{auth}" -- "${cur}") )
                fi
                ;;
            esac
          }
          complete -F _sure_completion sure
        BASH
      end

      def render_zsh
        root = words(root_commands.keys)
        auth = words(subcommands_for("auth"))

        <<~ZSH
          #compdef sure

          _sure() {
            local -a commands

            if (( CURRENT == 2 )); then
              commands=(#{root})
              compadd -- $commands
              return
            fi

            case $words[2] in
              auth)
                if (( CURRENT == 3 )); then
                  commands=(#{auth})
                  compadd -- $commands
                fi
                ;;
            esac
          }

          _sure "$@"
        ZSH
      end

      def render_fish
        lines = [ "complete -c sure -f" ]

        root_commands.each do |name, operation|
          lines << "complete -c sure -n '__fish_use_subcommand' -a #{fish_quote(name)}" \
                   "#{description_flag(operation)}"
        end

        subcommands_for("auth").each do |name|
          lines << "complete -c sure -n '__fish_seen_subcommand_from auth' -a #{fish_quote(name)}"
        end

        GLOBAL_FLAGS.each do |flag|
          lines << "complete -c sure -l #{flag.delete_prefix('--')}"
        end

        lines.join("\n") + "\n"
      end

      def root_commands
        commands = {}
        implemented_operations.each do |operation|
          path = validated_path(operation)
          commands[path.first] ||= path.length == 1 ? operation : nil
          next unless path.length == 1

          Array(operation.aliases).each do |name|
            commands[name] ||= nil if name.to_s.match?(TOKEN)
          end
        end
        commands
      end

      def subcommands_for(parent)
        implemented_operations.filter_map do |operation|
          path = validated_path(operation)
          next unless path.length == 2 && path.first == parent

          path.last
        end.uniq
      end

      def implemented_operations
        @implemented_operations ||= catalog.implemented
      end

      def validated_path(operation)
        path = Array(operation.path).map(&:to_s)
        if path.empty?
          raise Errors::UsageError, "catalog entry #{operation.id} has no command path"
        end

        path.each { |token| validate_token!(operation.id, token) }
        path
      end

      def validate_token!(id, token)
        return if token.match?(TOKEN)

        raise Errors::UsageError,
              "catalog entry #{id} contains an unsafe completion token #{token.inspect}"
      end

      def words(values)
        Array(values).join(" ")
      end

      def description_flag(operation)
        description = operation&.summary.to_s.gsub(/[\r\n\t]/, " ").strip
        return "" if description.empty?

        " -d #{fish_quote(description)}"
      end

      def fish_quote(value)
        "'#{value.to_s.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")}'"
      end
    end
  end
end

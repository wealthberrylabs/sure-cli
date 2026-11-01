# frozen_string_literal: true

require_relative "../errors"

module Sure
  class Catalog
    # Keeps the catalog honest: valid risk values, unique paths, D-04 destructive
    # naming, and a one-to-one match with Thor's non-hidden leaf commands.
    class Validator
      VALID_RISKS = %w[read local_write raw_write destructive].freeze

      # Thor generates a help task for every subcommand group. It is not a
      # product command, so it is excluded from the tree comparison.
      GENERATED_SUBCOMMANDS = %w[help].freeze

      def self.validate!(catalog, application = nil)
        new(catalog, application || Sure::CLI::Application).validate!
      end

      def initialize(catalog, application)
        @catalog = catalog
        @application = application
      end

      def validate!
        validate_risks!
        validate_duplicate_paths!
        validate_aliases!
        validate_destructive_paths!
        validate_command_tree!
        true
      end

      private

      def validate_risks!
        invalid = @catalog.all.reject { |entry| VALID_RISKS.include?(entry.risk) }
        return if invalid.empty?

        raise Errors::GeneralError,
              "catalog entries have an invalid risk: " \
              "#{invalid.map { |entry| "#{entry.id} (#{entry.risk.inspect})" }.sort.join(', ')}"
      end

      def validate_duplicate_paths!
        duplicates = @catalog.all.group_by(&:path).select { |_path, entries| entries.length > 1 }
        return if duplicates.empty?

        described = duplicates.map { |path, entries| "#{path.join(' ')} (#{entries.map(&:id).join(', ')})" }
        raise Errors::GeneralError, "duplicate catalog paths: #{described.sort.join(', ')}"
      end

      def validate_aliases!
        offenders = @catalog.all.select do |entry|
          entry.aliases.any? { |name| name.downcase == "rm" }
        end
        return if offenders.empty?

        raise Errors::GeneralError,
              "catalog entries must not declare an rm alias (D-04): " \
              "#{offenders.map(&:id).sort.join(', ')}"
      end

      def validate_destructive_paths!
        offenders = @catalog.all.select(&:destructive?).reject { |entry| entry.path.last == "delete" }
        return if offenders.empty?

        raise Errors::GeneralError,
              "destructive catalog entries must end in delete (D-04): " \
              "#{offenders.map(&:id).sort.join(', ')}"
      end

      def validate_command_tree!
        thor_paths = thor_leaf_paths
        catalog_paths = @catalog.implemented.map(&:path)

        missing = @catalog.implemented.reject { |entry| thor_paths.include?(entry.path) }
        unless missing.empty?
          raise Errors::GeneralError,
                "catalog entries have no matching command: #{missing.map(&:id).sort.join(', ')}"
        end

        orphans = thor_paths.reject { |path| catalog_paths.include?(path) }
        return if orphans.empty?

        raise Errors::GeneralError,
              "commands have no catalog entry: " \
              "#{orphans.map { |path| path.join(' ') }.sort.join(', ')}"
      end

      def thor_leaf_paths
        @thor_leaf_paths ||= begin
          paths = []
          @application.all_commands.each do |name, command|
            next if command.hidden?

            name = name.to_s
            if @application.subcommands.include?(name)
              paths.concat(subcommand_leaf_paths(name))
            else
              paths << [ name ]
            end
          end
          paths
        end
      end

      def subcommand_leaf_paths(name)
        subcommand_class(name).all_commands.filter_map do |sub_name, sub_command|
          next if sub_command.hidden?
          next if GENERATED_SUBCOMMANDS.include?(sub_name.to_s)

          [ name, sub_name.to_s ]
        end
      end

      def subcommand_class(name)
        @application.subcommand_classes.fetch(name.to_s)
      end
    end
  end
end

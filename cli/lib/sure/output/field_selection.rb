# frozen_string_literal: true

require_relative "../errors"

module Sure
  module Output
    # A comma-separated allowlist of top-level fields. Validation is shared by
    # every format: unknown names, empty segments, and duplicates are usage
    # errors (exit 2) so a typo never silently narrows output.
    class FieldSelection
      def initialize(spec)
        @names = parse(spec)
        freeze
      end

      attr_reader :names

      # Raises UsageError naming the first unknown field. Available names may be
      # column keys, labels, or record keys; comparison is case-insensitive and
      # treats spaces and underscores as equivalent.
      def validate!(available)
        known = Array(available).map { |name| normalize(name) }.reject(&:empty?).uniq
        @names.each do |name|
          next if known.include?(normalize(name))

          raise Errors::UsageError,
                "unknown field #{name.inspect}; available fields: #{known.sort.join(', ')}"
        end
        self
      end

      # Projects a Hash, or each element of an Array, by top-level key. Nested
      # values are preserved as-is (no dotted paths in Phase 1).
      def apply(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            result[key] = item if include?(key)
          end
        when Array
          value.map { |item| apply(item) }
        else
          value
        end
      end

      # Column indexes to keep, in the original order. Raises on unknown names.
      def indexes(headings)
        validate!(headings)
        headings.each_index.select { |index| include?(headings[index]) }
      end

      def include?(name)
        normalized = normalize(name)
        @names.any? { |candidate| normalize(candidate) == normalized }
      end

      def empty?
        @names.empty?
      end

      private

      def parse(spec)
        values = spec.is_a?(Array) ? spec : spec.to_s.split(",", -1)
        names = values.map { |value| value.to_s.strip }
        if names.any?(&:empty?)
          raise Errors::UsageError, "--fields must not contain an empty field"
        end

        normalized = names.map { |name| normalize(name) }
        duplicate = normalized.group_by(&:itself).find { |_name, entries| entries.length > 1 }
        if duplicate
          raise Errors::UsageError, "--fields lists #{duplicate.first.inspect} more than once"
        end

        names.freeze
      end

      def normalize(value)
        value.to_s.strip.downcase.tr(" ", "_")
      end
    end
  end
end

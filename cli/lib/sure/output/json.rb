# frozen_string_literal: true

require "json"
require "time"

require_relative "../http/pagination"
require_relative "../http/rate_limit"
require_relative "base"
require_relative "field_selection"

module Sure
  module Output
    # Emits exactly one compact JSON document plus a newline. The envelope is the
    # stable machine contract (D-12): schema_version, as_of, and warnings are
    # always present; server payloads never leak into it by default.
    class Json < Base
      SCHEMA_VERSION = 1
      NON_FINITE_WARNING = "non-finite numbers were replaced with null"
      RESERVED_META_KEYS = %w[schema_version as_of warnings].freeze

      def initialize(clock: Time, quiet: false)
        super(quiet: quiet)
        @clock = clock
      end

      def render(result, io:, fields: nil, stderr: nil)
        warnings = []
        data = normalize(result.data, warnings)
        if fields
          selection = fields.is_a?(FieldSelection) ? fields : FieldSelection.new(fields)
          data = apply_selection(data, selection, result)
        end

        meta = build_meta(result.meta, warnings)

        io.write(JSON.generate({ "data" => data, "meta" => meta }))
        io.write("\n")
        emit_warnings(stderr, warnings)
      end

      private

      COLLECTION_KEYS = %w[
        accounts transactions budgets rules holdings transfers tags items results data records checks
      ].freeze

      def apply_selection(data, selection, result)
        if result.columns
          selection.validate!(Array(result.columns).map(&:key))
          return selection.apply(data)
        end

        if data.is_a?(Hash) && (collection = collection_value(data))
          selection.validate!(collection_fields(collection))
          return data.each_with_object({}) do |(key, value), projected|
            projected[key] = key.to_s == collection_key(data) ? collection.map { |item| selection.apply(item) } : value
          end
        end

        selection.validate!(available_fields(data))
        selection.apply(data)
      end

      def collection_key(data)
        known = data.keys.find { |key| COLLECTION_KEYS.include?(key.to_s) && data[key].is_a?(Array) }
        return known unless known.nil?

        return nil unless data.key?("pagination") || data.key?(:pagination) || data.key?("meta") || data.key?(:meta)

        data.keys.find { |name| data[name].is_a?(Array) }
      end

      def collection_value(data)
        key = collection_key(data)
        key.nil? ? nil : data[key]
      end

      def collection_fields(collection)
        Array(collection).flat_map { |item| item.is_a?(Hash) ? item.keys.map(&:to_s) : [] }.uniq
      end

      def available_fields(data)
        case data
        when Hash then data.keys.map(&:to_s)
        when Array
          data.flat_map { |item| item.is_a?(Hash) ? item.keys.map(&:to_s) : [] }.uniq
        else []
        end
      end

      def build_meta(source, warnings)
        meta = stringify(source || {})
        extra_warnings = Array(meta.delete("warnings"))
        all_warnings = extra_warnings + warnings

        output = {
          "schema_version" => SCHEMA_VERSION,
          "as_of" => now.utc.iso8601,
          "warnings" => all_warnings
        }
        meta.each do |key, value|
          next if RESERVED_META_KEYS.include?(key)

          normalized = normalize_meta(value, warnings)
          output[key] = normalized unless normalized.nil?
        end
        output
      end

      def normalize_meta(value, warnings)
        case value
        when Sure::HTTP::RateLimit, Sure::HTTP::Pagination
          stringify(value.to_h).transform_values { |item| normalize_meta(item, warnings) }
        when Hash
          stringify(value).transform_values { |item| normalize_meta(item, warnings) }
        when Array
          value.map { |item| normalize_meta(item, warnings) }
        else
          normalize_scalar(value, warnings)
        end
      end

      def normalize_scalar(value, warnings)
        if value.is_a?(Float) && !value.finite?
          warnings << NON_FINITE_WARNING unless warnings.include?(NON_FINITE_WARNING)
          nil
        else
          value
        end
      end

      def normalize(value, warnings)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key] = normalize(item, warnings) }
        when Array
          value.map { |item| normalize(item, warnings) }
        when Float
          normalize_scalar(value, warnings)
        else
          value
        end
      end

      def stringify(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
      end

      def now
        @clock.respond_to?(:now) ? @clock.now : @clock
      end
    end
  end
end

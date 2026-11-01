# frozen_string_literal: true

require "json"

require_relative "base"
require_relative "field_selection"

module Sure
  module Output
    # Newline-delimited JSON: one compact object per data item. When --fields is
    # set, each object is projected before it is written.
    class Ndjson < Base
      COLLECTION_KEYS = %w[
        accounts transactions budgets rules holdings transfers tags items results data records checks
      ].freeze

      def render(result, io:, fields: nil, stderr: nil)
        items = items_for(result)
        selection = fields.is_a?(FieldSelection) ? fields : (fields && FieldSelection.new(fields))
        if selection
          selection.validate!(available_fields(items))
          items = items.map { |item| selection.apply(item) }
        end

        items.each do |item|
          io.write(JSON.generate(normalize(item)))
          io.write("\n")
        end
        emit_warnings(stderr, warnings(result))
      end

      private

      def items_for(result)
        data = result.data
        return result.data.is_a?(Hash) ? [ result.data ] : Array(result.data) if result.columns

        case data
        when Array then data
        when Hash then collection_value(data) || [ data ]
        when nil then []
        else [ data ]
        end
      end

      def collection_value(data)
        known = data.keys.find { |key| COLLECTION_KEYS.include?(key.to_s) && data[key].is_a?(Array) }
        return data[known] if known

        return nil unless data.key?("pagination") || data.key?(:pagination) || data.key?("meta") || data.key?(:meta)

        key = data.keys.find { |name| data[name].is_a?(Array) }
        key.nil? ? nil : data[key]
      end

      def available_fields(items)
        items.flat_map { |item| item.is_a?(Hash) ? item.keys.map(&:to_s) : [] }.uniq
      end

      # Infinite/NaN floats are not valid JSON; replace them with null.
      def normalize(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, item), result| result[key.to_s] = normalize(item) }
        when Array
          value.map { |item| normalize(item) }
        when Float
          value.finite? ? value : nil
        else
          value
        end
      end

      def warnings(result)
        Array(result.meta&.dig(:warnings) || result.meta&.dig("warnings"))
      end
    end
  end
end

# frozen_string_literal: true

require "csv"

require_relative "base"
require_relative "field_selection"

module Sure
  module Output
    # Machine-readable CSV. Quoting is delegated to CSV.generate; the only
    # extra work is neutralising spreadsheet formulas in non-numeric text cells
    # so a server-controlled value cannot execute in a spreadsheet.
    class Csv < Base
      COLLECTION_KEYS = %w[
        accounts transactions budgets rules holdings transfers tags items results data records checks
      ].freeze
      FORMULA_PREFIX = /\A[=+\-@]/
      NUMERIC = /\A[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?\z/
      # Remove terminal control characters while leaving embedded newlines for
      # CSV's own quoting to handle.
      FORMAT_CONTROLS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

      def render(result, io:, fields: nil, stderr: nil)
        headings, rows = frame(result)
        selection = fields.is_a?(FieldSelection) ? fields : (fields && FieldSelection.new(fields))
        if selection
          indexes = selection.indexes(headings)
          headings = indexes.map { |index| headings[index] }
          rows = rows.map { |row| indexes.map { |index| row[index] } }
        end

        csv = CSV.generate do |output|
          output << headings
          rows.each { |row| output << row.map { |cell| csv_cell(cell) } }
        end

        io.write(csv)
        emit_warnings(stderr, warnings(result))
      end

      private

      def frame(result)
        if result.columns
          columns = Array(result.columns)
          headings = columns.map(&:key)
          source = result.data.is_a?(Hash) ? [ result.data ] : Array(result.data)
          rows = source.map do |row|
            if row.is_a?(Hash)
              columns.map { |column| value_for(row, column.key) }
            else
              Array(row).first(columns.length)
            end
          end
          [ headings, rows ]
        else
          infer_frame(result.data)
        end
      end

      def infer_frame(data)
        rows = collection_rows(data)
        if rows.empty?
          return [ [], [] ]
        end

        if rows.all? { |row| row.is_a?(Hash) }
          headers = rows.flat_map(&:keys).map(&:to_s).uniq
          body = rows.map { |row| headers.map { |key| value_for(row, key) } }
          [ headers, body ]
        else
          [ [ "value" ], rows.map { |row| [ row ] } ]
        end
      end

      def collection_rows(data)
        case data
        when Array
          data
        when Hash
          collection_value(data) || [ data ]
        when nil
          []
        else
          [ data ]
        end
      end

      def collection_value(data)
        known = data.keys.find { |key| COLLECTION_KEYS.include?(key.to_s) && data[key].is_a?(Array) }
        return data[known] if known

        return nil unless data.key?("pagination") || data.key?(:pagination) || data.key?("meta") || data.key?(:meta)

        key = data.keys.find { |name| data[name].is_a?(Array) }
        key.nil? ? nil : data[key]
      end

      def value_for(row, key)
        return row[key] if row.key?(key)
        return row[key.to_sym] if row.key?(key.to_sym)

        nil
      end

      def csv_cell(value)
        text = case value
        when nil then ""
        when Hash, Array then safe_json(value)
        else value.to_s
        end
        text = text.gsub(FORMAT_CONTROLS, "")

        formula_text?(value, text) ? "'#{text}" : text
      end

      # Numeric negatives such as -12.34 are data, not formulas.
      def formula_text?(value, text)
        return false if value.is_a?(Numeric)
        return false if text.match?(NUMERIC)

        text.match?(FORMULA_PREFIX)
      end

      def warnings(result)
        Array(result.meta&.dig(:warnings) || result.meta&.dig("warnings"))
      end
    end
  end
end

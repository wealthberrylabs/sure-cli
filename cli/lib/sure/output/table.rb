# frozen_string_literal: true

require "terminal-table"

require_relative "base"

module Sure
  module Output
    # Human-readable table. Columns are explicit when a command supplies them;
    # otherwise (`sure api`) they are inferred from arbitrary JSON without ever
    # raising on an unexpected shape.
    class Table < Base
      COLLECTION_KEYS = %w[
        accounts transactions budgets rules holdings transfers tags items results data records
      ].freeze

      def initialize(color: false)
        super()
        @color = color
      end

      attr_reader :color

      def render(result, io:, fields: nil, stderr: nil)
        headings, rows = frame(result)
        headings, rows = select_fields(headings, rows, fields) if fields

        io.puts(build_table(headings, rows, result.columns).render)
        io.puts(result.footer) unless result.footer.nil? || result.footer.to_s.empty?
        emit_warnings(stderr, Array(result.meta&.dig(:warnings) || result.meta&.dig("warnings")))
      end

      private

      def frame(result)
        return explicit_frame(result) unless result.columns.nil?

        infer_frame(result.data)
      end

      def explicit_frame(result)
        columns = Array(result.columns)
        source = result.data.is_a?(Hash) ? [ result.data ] : Array(result.data)
        rows = source.map do |row|
          if row.is_a?(Hash)
            columns.map { |column| format_cell(column, value_for(row, column.key)) }
          else
            values = Array(row)
            values.each_with_index.map do |value, index|
              columns[index] ? format_cell(columns[index], value) : display(value)
            end
          end
        end
        [ columns.map(&:label), rows ]
      end

      def format_cell(column, value)
        display(column.format(value))
      end

      def infer_frame(data)
        case data
        when Array then infer_array(data)
        when Hash then infer_hash(data)
        when nil then [ [ "Value" ], [] ]
        else [ [ "Value" ], [ [ display(data) ] ] ]
        end
      rescue StandardError
        [ [ "Value" ], [ [ display(data) ] ] ]
      end

      def infer_array(data)
        return [ [ "Value" ], [] ] if data.empty?

        first = data.first
        return [ [ "Value" ], data.map { |item| [ display(item) ] } ] unless first.is_a?(Hash)

        keys = data.flat_map { |item| item.is_a?(Hash) ? item.keys : [] }.uniq.map(&:to_s)
        headings = keys.map { |key| Column.humanize(key) }
        rows = data.map do |item|
          keys.map { |key| display(value_for(item, key)) }
        end
        [ headings, rows ]
      end

      def infer_hash(data)
        return [ [ "Key", "Value" ], [] ] if data.empty?

        collection = collection_value(data)
        return infer_array(collection) if collection

        rows = data.map { |key, value| [ display(Column.humanize(key)), display(value) ] }
        [ [ "Key", "Value" ], rows ]
      end

      # A known collection key, or any array value in a paginated envelope,
      # becomes the table's rows.
      def collection_value(data)
        known = data.keys.find { |key| COLLECTION_KEYS.include?(key.to_s) && data[key].is_a?(Array) }
        return data[known] if known

        return nil unless data.key?("pagination") || data.key?("meta")

        key = data.keys.find { |name| data[name].is_a?(Array) }
        key.nil? ? nil : data[key]
      end

      def value_for(item, key)
        return item[key] if item.key?(key)
        return item[key.to_sym] if item.key?(key.to_sym)

        nil
      end

      def select_fields(headings, rows, fields)
        names = Array(fields).map(&:to_s)
        indexes = headings.each_index.select { |index| names.include?(headings[index].to_s.downcase) }
        indexes = headings.each_index.select do |index|
          names.include?(Column.humanize(headings[index]).downcase)
        end if indexes.empty?

        [ indexes.map { |index| headings[index] }, rows.map { |row| indexes.map { |index| row[index] } } ]
      end

      def build_table(headings, rows, columns = nil)
        table = Terminal::Table.new(headings: headings, rows: rows)
        Array(columns).each_with_index do |column, index|
          table.align_column(index, column.align)
        end
        table
      end
    end
  end
end

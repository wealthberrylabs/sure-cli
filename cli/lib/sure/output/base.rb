# frozen_string_literal: true

require "json"

require_relative "../errors"
require_relative "column"
require_relative "field_selection"
require_relative "result"

module Sure
  module Output
    # The only rendering entry point: a command passes a Result, a formatter
    # writes data to stdout and warnings to stderr.
    class Base
      # C0 controls other than tab/newline/carriage return, plus DEL. Removing
      # them keeps server-controlled strings from emitting terminal escapes.
      CONTROL_CHARACTERS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
      LINE_BREAKS = /[\r\n\t]/

      def initialize(quiet: false)
        @quiet = quiet
      end

      attr_reader :quiet

      def render(_result, io:, fields: nil, stderr: nil)
        raise NotImplementedError, "#{self.class} must implement #render"
      end

      protected

      def project(value, fields)
        selection = fields.is_a?(FieldSelection) ? fields : FieldSelection.new(fields)
        selection.apply(value)
      end

      def emit_warnings(stderr, warnings)
        return if quiet || stderr.nil? || warnings.nil? || warnings.empty?

        warnings.each { |warning| stderr.puts("warning: #{warning}") }
      end

      def display(value)
        text = case value
        when nil then ""
        when String then value
        when Hash, Array then safe_json(value)
        else value.to_s
        end

        sanitize(text)
      end

      # Table cells must be inert: no terminal control sequences and no
      # embedded line breaks that could reshape the table.
      def sanitize(text)
        text.to_s.gsub(CONTROL_CHARACTERS, "").gsub(LINE_BREAKS, " ")
      end

      def safe_json(value)
        JSON.generate(value)
      rescue StandardError
        value.inspect
      end
    end
  end
end

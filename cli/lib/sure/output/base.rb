# frozen_string_literal: true

require "json"

require_relative "../errors"
require_relative "column"
require_relative "result"

module Sure
  module Output
    # The only rendering entry point: a command passes a Result, a formatter
    # writes data to stdout and warnings to stderr.
    class Base
      def render(_result, io:, fields: nil, stderr: nil)
        raise NotImplementedError, "#{self.class} must implement #render"
      end

      protected

      def project(value, fields)
        names = Array(fields).map(&:to_s)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), result|
            result[key] = item if names.include?(key.to_s)
          end
        when Array
          value.map { |item| project(item, names) }
        else
          value
        end
      end

      def emit_warnings(stderr, warnings)
        return if stderr.nil? || warnings.nil? || warnings.empty?

        warnings.each { |warning| stderr.puts("warning: #{warning}") }
      end

      def display(value)
        case value
        when nil then ""
        when String then value
        when Hash, Array then safe_json(value)
        else value.to_s
        end
      end

      def safe_json(value)
        JSON.generate(value)
      rescue StandardError
        value.inspect
      end
    end
  end
end

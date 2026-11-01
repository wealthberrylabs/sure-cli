# frozen_string_literal: true

require "thor"

require_relative "../catalog"
require_relative "context"
require_relative "runtime"

module Sure
  module CLI
    # Shared behavior for the root application and command classes.
    class Base < Thor
      NOT_IMPLEMENTED = "not implemented until its plan lands"

      class << self
        # Builds a Thor description that starts with the catalog description and
        # appends the catalog-backed examples.
        def catalog_long_desc(id)
          entry = Sure::Catalog.fetch(id)
          lines = [entry.description.strip]
          unless entry.examples.empty?
            lines << ""
            lines << "Examples:"
            entry.examples.each { |example| lines << "  #{example}" }
          end
          lines.join("\n")
        end
      end

      no_commands do
        def runtime
          @runtime ||= Runtime.current
        end

        def context
          Context.current
        end
      end
    end
  end
end

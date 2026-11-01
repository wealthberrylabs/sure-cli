# frozen_string_literal: true

require "yaml"

require_relative "../errors"

module Sure
  class Catalog
    # Loads the machine-readable command catalog from the gem, not the current
    # working directory, so `sure` works from any shell and from an installed gem.
    class Loader
      DEFAULT_PATH = File.expand_path("../../../config/operations.yml", __dir__)

      def self.load(path = nil)
        new(path).load
      end

      def initialize(path = nil)
        @path = path ? File.expand_path(path) : DEFAULT_PATH
      end

      attr_reader :path

      def load
        data = YAML.safe_load_file(path, aliases: false)
        unless data.is_a?(Hash)
          raise Errors::GeneralError, "operation catalog #{path} must be a YAML mapping"
        end

        data
      rescue Psych::Exception => e
        raise Errors::GeneralError, "operation catalog #{path} is not valid YAML: #{e.message}"
      rescue Errno::ENOENT
        raise Errors::GeneralError, "operation catalog #{path} does not exist"
      end
    end
  end
end

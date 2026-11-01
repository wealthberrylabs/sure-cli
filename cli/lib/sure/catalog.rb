# frozen_string_literal: true

require_relative "errors"
require_relative "catalog/operation"
require_relative "catalog/loader"
require_relative "catalog/validator"

module Sure
  # Machine-readable command catalog: the single source for help examples,
  # completion, and later copyable commands.
  class Catalog
    SCHEMA_VERSION = 1

    class << self
      def load(path = nil)
        new(Loader.load(path))
      end

      def default
        @default ||= load
      end

      def fetch(id)
        default.fetch(id)
      end
    end

    def initialize(data)
      @schema_version = data["schema_version"]
      @commands = build_commands(data.fetch("commands", {}))
      freeze
    end

    attr_reader :schema_version

    def fetch(id)
      @commands.fetch(id.to_s) do
        raise Errors::NotFoundError, "unknown command catalog entry: #{id}"
      end
    end

    def all
      @commands.values
    end

    def implemented
      all.select(&:implemented?)
    end

    def planned
      all.select(&:planned?)
    end

    def ids
      @commands.keys
    end

    private

    def build_commands(raw)
      unless raw.is_a?(Hash)
        raise Errors::GeneralError, "operation catalog `commands` must be a mapping"
      end

      raw.each_with_object({}) do |(id, attributes), memo|
        memo[id.to_s] = build_operation(id.to_s, attributes)
      end
    end

    def build_operation(id, attributes)
      unless attributes.is_a?(Hash)
        raise Errors::GeneralError, "operation catalog entry #{id} must be a mapping"
      end

      Operation.new(
        id: id,
        path: Array(attributes["path"]).map(&:to_s).freeze,
        summary: attributes["summary"].to_s,
        description: attributes["description"].to_s,
        risk: attributes["risk"].to_s,
        status: attributes["status"].to_s,
        aliases: Array(attributes["aliases"]).map(&:to_s).freeze,
        arguments: build_arguments(id, attributes["arguments"]),
        options: build_options(id, attributes["options"]),
        examples: Array(attributes["examples"]).map(&:to_s).freeze,
        api: attributes["api"] || {},
        version_added: attributes["version_added"]
      )
    end

    def build_arguments(id, raw)
      Array(raw).map do |argument|
        unless argument.is_a?(Hash)
          raise Errors::GeneralError, "operation catalog entry #{id} has an invalid argument"
        end

        Argument.new(
          name: argument.fetch("name").to_s,
          required: argument.key?("required") ? argument["required"] : true,
          description: argument["description"]
        )
      end.freeze
    end

    def build_options(id, raw)
      Array(raw).map do |option|
        unless option.is_a?(Hash)
          raise Errors::GeneralError, "operation catalog entry #{id} has an invalid option"
        end

        Option.new(
          name: option.fetch("name").to_s,
          type: option.fetch("type", "string").to_s,
          description: option["description"]
        )
      end.freeze
    end
  end
end

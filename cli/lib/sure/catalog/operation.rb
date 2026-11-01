# frozen_string_literal: true

module Sure
  class Catalog
    # One catalog entry. Immutable; typed accessors keep callers away from raw
    # YAML hashes.
    Operation = Data.define(
      :id,
      :path,
      :summary,
      :description,
      :risk,
      :status,
      :aliases,
      :arguments,
      :options,
      :examples,
      :api,
      :version_added
    ) do
      def planned?
        status == "planned"
      end

      def implemented?
        status == "implemented"
      end

      def destructive?
        risk == "destructive"
      end
    end

    Argument = Data.define(:name, :required, :description) do
      def initialize(name:, required: true, description: nil)
        super(name: name, required: required, description: description)
      end
    end

    Option = Data.define(:name, :type, :description) do
      def initialize(name:, type: "string", description: nil)
        super(name: name, type: type, description: description)
      end
    end
  end
end

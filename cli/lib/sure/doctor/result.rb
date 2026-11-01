# frozen_string_literal: true

module Sure
  module Doctor
    # One immutable diagnostic outcome. Status is :pass, :warn, :fail, or :skip;
    # #to_h renders the labels used by both JSON and human output.
    Result = Data.define(:id, :label, :status, :detail, :fix) do
      STATUSES = %i[pass warn fail skip].freeze

      def initialize(id:, label:, status:, detail: nil, fix: nil)
        status = status.to_sym
        raise ArgumentError, "unknown doctor status #{status.inspect}" unless STATUSES.include?(status)

        super(id: id.to_s, label: label.to_s, status: status, detail: detail, fix: fix)
      end

      def pass?
        status == :pass
      end

      def warn?
        status == :warn
      end

      def fail?
        status == :fail
      end

      def skip?
        status == :skip
      end

      def to_h
        {
          "id" => id,
          "label" => label,
          "status" => status.to_s.upcase,
          "detail" => detail,
          "fix" => fix
        }
      end
    end
  end
end

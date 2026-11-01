# frozen_string_literal: true

module Sure
  module Output
    # One table column: a data key, a human label, an alignment, and an optional
    # formatter. Formatters receive the raw value and return a display string.
    Column = Data.define(:key, :label, :align, :formatter) do
      ALIGNMENTS = %i[left center right].freeze

      def initialize(key:, label: nil, align: :left, formatter: nil)
        align = align.to_sym
        raise ArgumentError, "align must be one of #{ALIGNMENTS.join(', ')}" unless ALIGNMENTS.include?(align)

        super(
          key: key.to_s,
          label: (label || humanize(key)).to_s,
          align: align,
          formatter: formatter
        )
      end

      def format(value)
        formatter ? formatter.call(value) : value
      end

      def self.humanize(key)
        key.to_s.split("_").map(&:capitalize).join(" ")
      end
    end
  end
end

# frozen_string_literal: true

require_relative "pagination"

module Sure
  module HTTP
    # Normalizes the two collection shapes Sure's API returns into one
    # {data:, pagination:} value. Values are preserved as-is; money is never
    # reformatted and totals are never recomputed here.
    module Envelope
      PAGE_CONTAINER_KEYS = %w[pagination meta].freeze

      # Returns { data: <Array|Hash>, pagination: Pagination|nil }.
      def self.normalize(payload, collection_key: nil)
        return { data: payload, pagination: nil } unless payload.is_a?(Hash)

        {
          data: extract_data(payload, collection_key),
          pagination: Pagination.from_hash(pagination_source(payload))
        }
      end

      def self.extract_data(payload, collection_key)
        if collection_key
          key = find_key(payload, collection_key)
          return payload[key] unless key.nil?
        end

        data_key = find_key(payload, "data")
        return payload[data_key] unless data_key.nil?

        container = payload.keys.find do |key|
          !PAGE_CONTAINER_KEYS.include?(key.to_s) && payload[key].is_a?(Array)
        end
        container.nil? ? payload : payload[container]
      end

      def self.pagination_source(payload)
        PAGE_CONTAINER_KEYS.each do |name|
          key = find_key(payload, name)
          return payload[key] if !key.nil? && payload[key].is_a?(Hash)
        end
        nil
      end

      def self.find_key(payload, name)
        payload.keys.find { |key| key.to_s == name.to_s }
      end

      private_class_method :extract_data, :pagination_source, :find_key
    end
  end
end

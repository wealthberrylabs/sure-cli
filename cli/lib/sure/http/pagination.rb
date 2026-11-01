# frozen_string_literal: true

require_relative "../errors"

module Sure
  module HTTP
    # A validated page cursor. The server defaults to 25 and clamps to 100, so
    # the CLI refuses values outside 1..100 instead of silently changing a
    # request the user asked for.
    class Pagination
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100
      MESSAGE = "per_page must be an integer between 1 and 100"

      attr_reader :page, :per_page, :total_count, :total_pages, :prev_page, :explicit_next_page

      def self.from_hash(source)
        return nil unless source.is_a?(Hash)

        new(
          page: source["page"] || source["current_page"] || 1,
          per_page: source["per_page"],
          total_count: source["total_count"],
          total_pages: source["total_pages"],
          prev_page: source["prev_page"],
          next_page: source.key?("next_page") ? source["next_page"] : :derive
        )
      end

      def self.validate_per_page!(value)
        return DEFAULT_PER_PAGE if value.nil?
        return value if value.is_a?(Integer) && value.between?(1, MAX_PER_PAGE)

        text = value.to_s.strip
        raise Errors::UsageError, MESSAGE if text.empty?

        number = Integer(text, 10)
        raise Errors::UsageError, MESSAGE unless number.between?(1, MAX_PER_PAGE)

        number
      rescue ArgumentError, TypeError
        raise Errors::UsageError, MESSAGE
      end

      def initialize(page: 1, per_page: nil, total_count: nil, total_pages: nil,
                     prev_page: nil, next_page: :derive)
        @page = positive_integer(page) || 1
        @per_page = self.class.validate_per_page!(per_page)
        @total_count = optional_integer(total_count)
        @total_pages = optional_integer(total_pages)
        @prev_page = optional_integer(prev_page)
        @explicit_next_page = next_page == :derive ? :derive : optional_integer(next_page)
        freeze
      end

      def next_page?
        !next_page.nil?
      end

      def next_page
        return @explicit_next_page unless @explicit_next_page == :derive
        return nil if @total_pages.nil?

        page < @total_pages ? page + 1 : nil
      end

      def params_for(page_number)
        { page: positive_integer(page_number) || 1, per_page: per_page }
      end

      def to_h
        {
          "page" => page,
          "per_page" => per_page,
          "total_count" => total_count,
          "total_pages" => total_pages,
          "next_page" => next_page
        }.compact
      end

      private

      def positive_integer(value)
        number = optional_integer(value)
        number&.positive? ? number : nil
      end

      def optional_integer(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        Integer(value.to_s, 10)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end

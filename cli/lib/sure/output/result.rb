# frozen_string_literal: true

module Sure
  module Output
    # The non-secret facts a command asks a formatter to render. Commands build
    # this; formatters decide how it reaches stdout.
    Result = Data.define(:data, :meta, :columns, :footer) do
      def initialize(data: nil, meta: nil, columns: nil, footer: nil)
        super(
          data: data,
          meta: (meta || {}).freeze,
          columns: columns,
          footer: footer
        )
      end
    end
  end
end

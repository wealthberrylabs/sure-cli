# frozen_string_literal: true

require "thor"

module Sure
  module CLI
    # Routes Thor's built-in help and error output through the injected runtime
    # so `sure help` is captured by StringIO in tests and never writes to the
    # real terminal.
    class Shell < Thor::Shell::Basic
      def initialize(runtime)
        super()
        @runtime = runtime
      end

      protected

      def stdout
        @runtime.stdout
      end

      def stderr
        @runtime.stderr
      end

      def can_display_colors?
        false
      end
    end
  end
end

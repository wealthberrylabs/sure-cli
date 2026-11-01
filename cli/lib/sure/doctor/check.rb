# frozen_string_literal: true

module Sure
  module Doctor
    # One ordered checklist entry. `run` names a private Runner method so checks
    # stay pure definitions and the runner owns state and dependencies.
    Check = Data.define(:id, :label, :run, :fix) do
      def initialize(id:, label:, run:, fix: nil)
        super(id: id.to_sym, label: label.to_s, run: run.to_sym, fix: fix)
      end
    end
  end
end

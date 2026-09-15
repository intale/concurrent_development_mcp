# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class ProgressDecisionV1 < Value
        attribute :outcome, Types::String.enum("advanced", "completed", "existing")
        attribute :plan, EventPlan.optional
      end
    end
  end
end

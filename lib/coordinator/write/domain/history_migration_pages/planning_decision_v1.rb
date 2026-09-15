# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class PlanningDecisionV1 < Value
        attribute :outcome, Types::String.enum("planned", "existing")
        attribute :plan, EventPlan.optional
      end
    end
  end
end

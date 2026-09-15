# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class ApplicationProgressDecisionV1 < Value
        attribute :outcome, Types::String.enum("advanced", "existing")
        attribute :plan, EventPlan.optional
      end
    end
  end
end

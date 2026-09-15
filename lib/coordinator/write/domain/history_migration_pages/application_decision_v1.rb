# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class ApplicationDecisionV1 < Value
        attribute :outcome, Types::String.enum("applied", "existing")
        attribute :plan, EventPlan.optional
      end
    end
  end
end

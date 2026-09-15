# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrationPages
      class CreationDecisionV1 < Value
        attribute :outcome, Types::String.enum("created", "existing")
        attribute :plan, EventPlan.optional
      end
    end
  end
end

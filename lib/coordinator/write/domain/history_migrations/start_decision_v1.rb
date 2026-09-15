# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module HistoryMigrations
      class StartDecisionV1 < Value
        attribute :outcome, Types::String.enum("started", "existing")
        attribute :plan, Types.Instance(EventPlan).optional
      end
    end
  end
end

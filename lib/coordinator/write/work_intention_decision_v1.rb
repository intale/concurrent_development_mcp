# frozen_string_literal: true

module Coordinator::Write
  class WorkIntentionDecisionV1 < Value
    Plan = Types.Instance(Domain::EventPlan)

    attribute :kind, Types::String.enum("write", "no_change")
    attribute :plan, Plan.optional

    def self.write(plan)
      new(kind: "write", plan:)
    end

    def self.no_change
      new(kind: "no_change", plan: nil)
    end

    def write?
      kind == "write"
    end
  end
end

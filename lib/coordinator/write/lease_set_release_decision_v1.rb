# frozen_string_literal: true

module Coordinator::Write
  class LeaseSetReleaseDecisionV1 < Value
    Plan = Types.Instance(Domain::EventPlan)

    attribute :kind, Types::String.enum("release", "already_released")
    attribute :plan, Plan.optional

    def self.release(plan)
      new(kind: "release", plan:)
    end

    def self.already_released
      new(kind: "already_released", plan: nil)
    end

    def release?
      kind == "release"
    end
  end
end

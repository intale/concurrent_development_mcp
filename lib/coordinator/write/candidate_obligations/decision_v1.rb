# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class DecisionV1 < Value
      Plan = Types.Instance(Domain::EventPlan)

      attribute :outcome, Types::CandidateObligationDecisionOutcome
      attribute :plan, Plan.optional
      attribute :obligation, Events::VerificationObligationCreatedV1.optional

      def self.created(plan, obligation)
        new(outcome: "created", plan:, obligation:)
      end

      def self.replayed(obligation)
        new(outcome: "replayed", plan: nil, obligation:)
      end

      def self.no_event(outcome)
        new(outcome:, plan: nil, obligation: nil)
      end
    end
  end
end

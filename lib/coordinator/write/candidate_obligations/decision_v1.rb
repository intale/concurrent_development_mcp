# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class DecisionV1 < Value
      Plan = Types.Instance(Domain::EventPlan)

      attribute :outcome, Types::CandidateObligationDecisionOutcome
      attribute :plan, Plan.optional
      Obligation = Types.Instance(Events::VerificationObligationCreatedV2) |
        Types.Instance(VerificationObligations::DefinitionV2)

      attribute :obligation, Obligation.optional

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

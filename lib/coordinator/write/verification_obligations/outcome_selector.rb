# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligations
    class OutcomeSelector
      def call(state:, triggering_evidence_id:)
        return OutcomeDecisionV1.none if state.terminal?

        trigger = state.observation(triggering_evidence_id)
        return OutcomeDecisionV1.none unless trigger
        return OutcomeDecisionV1.failed(trigger) if trigger.evidence.assessment.conclusion == "failed"
        return OutcomeDecisionV1.none unless trigger.evidence.assessment.conclusion == "passed"

        selected = state.passed_by_kind
        return OutcomeDecisionV1.none unless state.definition.required_evidence.all? { selected.key?(_1) }

        OutcomeDecisionV1.satisfied(state.definition.required_evidence.map { selected.fetch(_1) })
      end
    end
  end
end

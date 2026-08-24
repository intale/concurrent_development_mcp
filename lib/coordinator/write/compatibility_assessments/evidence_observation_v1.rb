# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class EvidenceObservationV1 < Value
      attribute :evidence, Types.Instance(Events::VerificationEvidenceSubmittedV1)
      attribute :event, EventReference

      def decision_reference
        EvidenceDecisionReferenceV1.new(
          evidence_kind: evidence.evidence_kind,
          evidence_id: evidence.evidence_id,
          conclusion: evidence.assessment.conclusion,
          result_digest: evidence.assessment.result_digest,
          assessment_input_digest: evidence.assessment_input_digest,
          event:
        )
      end
    end
  end
end

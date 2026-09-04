# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class EvidenceObservationV2 < Value
      attribute :evidence, Types.Instance(Events::VerificationEvidenceSubmittedV2)
      attribute :event, EventReference
      attribute :assessment_input_digest, Types::Sha256Digest
      attribute :obligation_validity_input_digest, Types::Sha256Digest
      attribute :policy, CandidateObligations::ImpactPolicyEvidenceV1

      def decision_reference
        EvidenceDecisionReferenceV1.new(
          evidence_kind: evidence.evidence_kind,
          evidence_id: evidence.evidence_id,
          conclusion: evidence.assessment.conclusion,
          result_digest: evidence.assessment.result_digest,
          assessment_input_digest:,
          event:
        )
      end
    end
  end
end

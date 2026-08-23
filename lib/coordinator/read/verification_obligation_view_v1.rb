# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationViewV1 < Value
    Reason = Coordinator::Write::CandidateObligations::ImpactReasonV1

    attribute :obligation_id, Types::Identifier
    attribute :kind, Types::VerificationObligationKind
    attribute :status, Types::VerificationObligationStatus
    attribute :change_set_id, Types::Identifier
    attribute :source_candidate, Coordinator::Write::CandidateObligations::CandidateSubjectV1
    attribute :target_candidate, Coordinator::Write::CandidateObligations::CandidateSubjectV1
    attribute :reasons, Types::Array.of(Reason).constrained(min_size: 1, max_size: 3)
    attribute :required_evidence, Types::CandidateImpactRequiredEvidenceKinds
    attribute :enforcement, Types::String.enum("verification_gate", "merge_gate")
    attribute :policy, Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1
    attribute :validity_input_digest, Types::Sha256Digest
    attribute :rule_version, Types::CandidateCompatibilityObligationRuleVersion
    attribute :created_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end

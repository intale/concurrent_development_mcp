# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ValidityDocumentV1 < Value
      SCHEMA = "candidate-compatibility-obligation-validity/v1"
      Reason = ImpactReasonV1

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :source_candidate, CandidateSubjectV1
      attribute :target_candidate, CandidateSubjectV1
      attribute :reasons, Types::Array.of(Reason).constrained(min_size: 1, max_size: 3)
      attribute :required_evidence, Types::CandidateImpactRequiredEvidenceKinds
      attribute :enforcement, Types::String.enum("verification_gate", "merge_gate")
      attribute :policy, ImpactPolicyEvidenceV1
      attribute :rule_version, Types::CandidateCompatibilityObligationRuleVersion
    end
  end
end

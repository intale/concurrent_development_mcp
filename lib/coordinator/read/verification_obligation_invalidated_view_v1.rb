# frozen_string_literal: true

module Coordinator::Read
  class VerificationObligationInvalidatedViewV1 < Value
    attribute :obligation_id, Types::Identifier
    attribute :obligation_event, Coordinator::Write::EventReference
    attribute :invalidated_policy, Coordinator::Write::CandidateObligations::ImpactPolicyEvidenceV1
    attribute :superseding_partition_event, Coordinator::Write::EventReference
    attribute :previous_status, Types::String.enum("open", "satisfied", "failed", "waived")
    attribute :previous_terminal_event, Coordinator::Write::EventReference.optional
    attribute :reason, Types::String.enum("policy_partition_advanced")
    attribute :invalidation_digest, Types::Sha256Digest
    attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    attribute :invalidated_at, Types::Timestamp
    attribute :evidence, VerificationObligationEvidenceV1
  end
end

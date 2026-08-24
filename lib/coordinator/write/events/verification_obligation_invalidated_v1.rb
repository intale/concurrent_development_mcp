# frozen_string_literal: true

module Coordinator::Write
  module Events
    class VerificationObligationInvalidatedV1 < Base
      contract type: "VerificationObligationInvalidated", version: 1

      attribute :obligation_id, Types::Identifier
      attribute :obligation_event, EventReference
      attribute :invalidated_policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :superseding_partition_event, EventReference
      attribute :previous_status, Types::String.enum("open", "satisfied", "failed", "waived")
      attribute :previous_terminal_event, EventReference.optional
      attribute :reason, Types::String.enum("policy_partition_advanced")
      attribute :invalidation_digest, Types::Sha256Digest
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
      attribute :invalidated_at, Types::Timestamp
    end
  end
end

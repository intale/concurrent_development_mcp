# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationInvalidations
    class DigestDocumentV1 < Value
      attribute :schema, Types::String.enum("verification-obligation-invalidation/v1")
      attribute :obligation_event, EventReference
      attribute :invalidated_policy, CandidateObligations::ImpactPolicyEvidenceV1
      attribute :superseding_partition_event, EventReference
      attribute :previous_status, Types::String.enum("open", "satisfied", "failed", "waived")
      attribute :previous_terminal_event, EventReference.optional
      attribute :reason, Types::String.enum("policy_partition_advanced")
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end

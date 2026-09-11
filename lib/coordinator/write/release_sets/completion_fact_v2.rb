# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompletionFactV2 < Value
      attribute :payload, Events::ReleaseSetOutcomeRecordedV1
      attribute :outcome_event, EventReference
      attribute :event, EventReference
      attribute :compensation_evidence,
                Types::Array.of(CompensationEvidenceV2)
                  .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :completion_digest, Types::Sha256Digest
      attribute :release_digest, Types::Sha256Digest
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    end
  end
end

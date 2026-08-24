# frozen_string_literal: true

module Coordinator::Write
  module Events
    class ReleaseSetCompletedV1 < Base
      Evidence = ReleaseSets::CompensationEvidenceV1

      contract type: "ReleaseSetCompleted", version: 1

      attribute :release_set_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :outcome, Types::ReleaseSetCompletionOutcome
      attribute :source_event, EventReference
      attribute :compensation_evidence,
                Types::Array.of(Evidence).constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :completion_digest, Types::Sha256Digest
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
      attribute :completed_at, Types::Timestamp
    end
  end
end

# frozen_string_literal: true

module Coordinator::Read
  class ReleaseSetCompletionViewV1 < Value
    Evidence = Coordinator::Write::ReleaseSets::CompensationEvidenceV2

    attribute :outcome, Types::ReleaseSetCompletionOutcome
    attribute :source_event, Coordinator::Write::EventReference.optional
    attribute :compensation_evidence,
              Types::Array.of(Evidence).constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
    attribute :completion_digest, Types::Sha256Digest
    attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    attribute :completed_at, Types::Timestamp
    attribute :source, ReleaseSetSourceEvidenceV1
  end
end

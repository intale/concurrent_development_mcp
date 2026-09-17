# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyReleaseCompletionDigestDocumentV1 < Value
      attribute :schema, Types::String.enum("release-set-completion/v1")
      attribute :release_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :outcome, Types::ReleaseSetCompletionOutcome
      attribute :source_event, EventReference
      attribute :compensation_evidence,
                Types::Array.of(ReleaseSets::CompensationEvidenceV1)
                  .constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    end
  end
end

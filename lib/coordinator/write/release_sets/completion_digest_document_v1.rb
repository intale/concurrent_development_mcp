# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompletionDigestDocumentV1 < Value
      Evidence = CompensationEvidenceV1

      attribute :schema, Types::String.enum("release-set-completion/v1")
      attribute :release_set_id, Types::Identifier
      attribute :release_digest, Types::Sha256Digest
      attribute :outcome, Types::ReleaseSetCompletionOutcome
      attribute :source_event, EventReference
      attribute :compensation_evidence,
                Types::Array.of(Evidence).constrained(max_size: Types::RELEASE_SET_MAXIMUM_MEMBERS)
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    end
  end
end

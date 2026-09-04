# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ReleaseSetOutcomeV1 < EventMetadata
      attribute :completion_digest, Types::Sha256Digest
      attribute :release_digest, Types::Sha256Digest
      attribute :rule_version, Types::ReleaseSetCompletionRuleVersion
    end
  end
end

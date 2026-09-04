# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ReleaseSetCompensationV2 < EventMetadata
      attribute :release_digest, Types::Sha256Digest
      attribute :rule_version, Types::ReleaseSetCompensationRuleVersion
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanSourceLinkedV1 < Base
      contract type: "CandidateImpactPairScanSourceLinked", version: 1

      attribute :scan_id, Types::UuidV7
      attribute :role, Types::String.enum("source_registration", "policy_partition", "policy_head")
      attribute :source, EventReference
    end
  end
end

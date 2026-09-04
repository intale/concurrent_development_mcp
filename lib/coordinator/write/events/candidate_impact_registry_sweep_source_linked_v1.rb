# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactRegistrySweepSourceLinkedV1 < Base
      contract type: "CandidateImpactRegistrySweepSourceLinked", version: 1

      attribute :scan_id, Types::UuidV7
      attribute :role, Types::String.enum("policy_partition", "policy_head")
      attribute :source, EventReference
    end
  end
end

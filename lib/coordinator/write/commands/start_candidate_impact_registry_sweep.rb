# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartCandidateImpactRegistrySweep < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :from_revision, Types::StreamRevision
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :rule_version, Types::CandidateImpactRegistrySweepRuleVersion
    end
  end
end

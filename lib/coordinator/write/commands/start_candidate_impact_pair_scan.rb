# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class StartCandidateImpactPairScan < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :source_registration, EventReference
      attribute :direction, Types::CandidateImpactQueryDirection
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :from_revision, Types::StreamRevision
      attribute :to_revision, Types::StreamRevisionCursor
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :index_policy_version, Types::CandidateImpactIndexPolicyVersion
      attribute :rule_version, Types::CandidateImpactPairScanRuleVersion
    end
  end
end

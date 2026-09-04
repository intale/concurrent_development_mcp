# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ProgressCandidateImpactRegistrySweep < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :scan_id, Types::UuidV7
      attribute :change_set_id, Types::Identifier
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :expected_checkpoint, EventReference
      attribute :previous_from_revision, Types::StreamRevision
      attribute :last_processed_revision, Types::StreamRevision.optional
      attribute :page_registration_count, Types::CandidateImpactScanPageRegistrationCount
      attribute :has_more, Types::Bool
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :rule_version, Types::CandidateImpactRegistrySweepRuleVersion
    end
  end
end

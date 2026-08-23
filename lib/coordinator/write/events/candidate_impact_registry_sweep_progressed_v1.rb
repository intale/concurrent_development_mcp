# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactRegistrySweepProgressedV1 < Base
      contract type: "CandidateImpactRegistrySweepProgressed", version: 1

      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :started_event, EventReference
      attribute :previous_checkpoint, EventReference
      attribute :previous_from_revision, Types::StreamRevision
      attribute :next_from_revision, Types::StreamRevision
      attribute :to_revision, Types::StreamRevision
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :page_number, Types::Integer.constrained(gteq: 1)
      attribute :page_registration_count, Types::CandidateImpactScanPageRegistrationCount
      attribute :total_registration_count, Types::Integer.constrained(gteq: 0)
      attribute :rule_version, Types::CandidateImpactRegistrySweepRuleVersion
      attribute :progressed_at, Types::Timestamp
    end
  end
end

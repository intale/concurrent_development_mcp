# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactRegistrySweepSkippedV1 < Base
      contract type: "CandidateImpactRegistrySweepSkipped", version: 1

      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :from_revision, Types::StreamRevision
      attribute :to_revision, Types::StreamRevisionCursor
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :reason, Types::CandidateImpactRegistrySweepSkipReason
      attribute :rule_version, Types::CandidateImpactRegistrySweepRuleVersion
      attribute :skipped_at, Types::Timestamp
    end
  end
end

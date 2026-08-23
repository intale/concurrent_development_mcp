# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanCompletedV1 < Base
      contract type: "CandidateImpactPairScanCompleted", version: 1

      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :source_registration, EventReference
      attribute :direction, Types::CandidateImpactQueryDirection
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :markers, Types::CandidateImpactPairScanMarkers
      attribute :started_event, EventReference
      attribute :previous_checkpoint, EventReference
      attribute :previous_from_revision, Types::StreamRevision
      attribute :final_from_revision, Types::StreamRevision
      attribute :to_revision, Types::StreamRevision
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :page_count, Types::Integer.constrained(gteq: 1)
      attribute :page_registration_count, Types::CandidateImpactScanPageRegistrationCount
      attribute :total_registration_count, Types::Integer.constrained(gteq: 0)
      attribute :index_policy_version, Types::CandidateImpactIndexPolicyVersion
      attribute :rule_version, Types::CandidateImpactPairScanRuleVersion
      attribute :completed_at, Types::Timestamp
    end
  end
end

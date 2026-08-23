# frozen_string_literal: true

module Coordinator::Write
  module Events
    class CandidateImpactPairScanSkippedV1 < Base
      contract type: "CandidateImpactPairScanSkipped", version: 1

      attribute :scan_id, Types::Identifier
      attribute :change_set_id, Types::Identifier
      attribute :source_registration, EventReference
      attribute :direction, Types::CandidateImpactQueryDirection
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :markers, Types::CandidateImpactPairScanMarkers
      attribute :from_revision, Types::StreamRevision
      attribute :to_revision, Types::StreamRevisionCursor
      attribute :page_size, Types::CandidateImpactScanPageSize
      attribute :reason, Types::CandidateImpactPairScanSkipReason
      attribute :index_policy_version, Types::CandidateImpactIndexPolicyVersion
      attribute :rule_version, Types::CandidateImpactPairScanRuleVersion
      attribute :skipped_at, Types::Timestamp
    end
  end
end

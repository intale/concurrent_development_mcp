# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module CandidateObligationScans
      class RegistrySweepState < Value
        attribute :status, Types::CandidateImpactScanStatus
        attribute :scan_id, Types::UuidV7.optional
        attribute :change_set_id, Types::Identifier.optional
        attribute :policy_partition_event, EventReference.optional
        attribute :policy_head, Coordinator::Write::Decisions::DecisionHeadV1.optional
        attribute :started_event, EventReference.optional
        attribute :checkpoint_event, EventReference.optional
        attribute :from_revision, Types::StreamRevision.optional
        attribute :to_revision, Types::StreamRevisionCursor.optional
        attribute :page_size, Types::CandidateImpactScanPageSize.optional
        attribute :page_count, Types::Integer.constrained(gteq: 0)
        attribute :rule_version, Types::CandidateImpactRegistrySweepRuleVersion.optional
        attribute :skip_reason, Types::CandidateImpactRegistrySweepSkipReason.optional

        def self.initial
          new(
            status: "absent",
            scan_id: nil,
            change_set_id: nil,
            policy_partition_event: nil,
            policy_head: nil,
            started_event: nil,
            checkpoint_event: nil,
            from_revision: nil,
            to_revision: nil,
            page_size: nil,
            page_count: 0,
            rule_version: nil,
            skip_reason: nil
          )
        end

        def absent? = status == "absent"
        def running? = status == "running"
        def terminal? = %w[skipped completed].include?(status)
      end
    end
  end
end

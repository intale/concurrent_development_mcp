# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionPartitionAdvancedV1 < Base
      contract type: "DecisionPartitionAdvanced", version: 1

      Head = Decisions::DecisionHeadV1

      attribute :partition, Decisions::DecisionPartitionV1
      attribute :partition_revision, Types::StreamRevision
      attribute :decision, Decisions::DecisionHeadV1
      attribute :active_decisions, Types::Array.of(Head).constrained(max_size: 32)
      attribute :change_kind, Types::DecisionChangeKind
      attribute :advanced_at, Types::Timestamp
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module DecisionContexts
    class PartitionObservationV1 < Value
      Head = Decisions::DecisionHeadV1

      attribute :partition, Decisions::DecisionPartitionV1
      attribute :partition_revision, Types::StreamRevision.optional
      attribute :event, EventReference.optional
      attribute :active_decisions, Types::Array.of(Head).constrained(max_size: 32)
    end
  end
end

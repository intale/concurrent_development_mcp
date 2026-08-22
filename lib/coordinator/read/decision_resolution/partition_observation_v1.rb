# frozen_string_literal: true

module Coordinator::Read
  module DecisionResolution
    class PartitionObservationV1 < Value
      Head = Coordinator::Write::Decisions::DecisionHeadV1

      attribute :partition, Coordinator::Write::Decisions::DecisionPartitionV1
      attribute :partition_revision, Types::StreamRevision.optional
      attribute :event, Coordinator::Write::EventReference.optional
      attribute :active_decisions, Types::Array.of(Head).constrained(max_size: 32)
    end
  end
end

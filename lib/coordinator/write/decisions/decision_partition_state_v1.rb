# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionPartitionStateV1 < Value
      Head = DecisionHeadV1

      attribute :partition, DecisionPartitionV1
      attribute :latest_revision, Types::StreamRevision.optional
      attribute :active_decisions, Types::Array.of(Head).constrained(max_size: 32)
    end
  end
end

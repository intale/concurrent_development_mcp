# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionPartitionStateV1 < Value
      attribute :partition, DecisionPartitionV1
      attribute :latest_revision, Types::StreamRevision.optional
    end
  end
end

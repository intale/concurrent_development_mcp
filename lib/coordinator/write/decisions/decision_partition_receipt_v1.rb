# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionPartitionReceiptV1 < Value
      attribute :partition, DecisionPartitionV1
      attribute :partition_revision, Types::StreamRevision
    end
  end
end

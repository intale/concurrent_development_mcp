# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionRemovedFromPartitionV1 < Base
      contract type: "DecisionRemovedFromPartition", version: 1

      attribute :partition_id, Types::Identifier
      attribute :partition_revision, Types::StreamRevision
      attribute :decision_id, Types::Identifier
    end
  end
end

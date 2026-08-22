# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionPartitionV1 < Value
      attribute :partition_id, Types::Identifier
      attribute :topic_root, Types::Identifier
      attribute :anchor_kind, Types::DecisionPartitionAnchorKind
      attribute :anchor_id, Types::Identifier
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionPartitionDeltaV1 < Value
      attribute :source_event, Types.Instance(PgEventstore::Event)
      attribute :source_payload, Types.Instance(Events::DecisionPartitionAdvancedV1)
      attribute :remove, Types::Bool
      attribute :add, Types::Bool
      attribute :first_target_revision, Types::StreamRevision
    end
  end
end

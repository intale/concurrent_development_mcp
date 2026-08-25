# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class SnapshotV1 < Value
      attribute :state, State
      attribute :physical_events, Types::Array.of(Types::Any)

      def physical_event(event_id)
        physical_events.find { _1.id == event_id }
      end
    end
  end
end

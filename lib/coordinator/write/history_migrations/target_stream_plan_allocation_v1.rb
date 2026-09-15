# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetStreamPlanAllocationV1 < Value
      attribute :plan_stream, StreamReference
      attribute :target_stream, StreamReference
      attribute :allocation_event, Types.Instance(PgEventstore::Event)
      attribute :outcome, Types::String.enum("created", "existing")
    end
  end
end

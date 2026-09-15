# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PlannedFactV1 < Value
      attribute :target_stream, StreamReference
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :target_event_marker, Types::ResourceMarker
      attribute :process_step, Types.Instance(ProcessSteps::PlannedV1)
      attribute :target_event_plan, TargetEventPlanV1
    end
  end
end

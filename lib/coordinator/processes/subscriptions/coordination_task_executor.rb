# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class CoordinationTaskExecutor < Coordinator::Shared::Subscriptions::Registration
      LANE_COUNT = Coordinator::Write::Tasks::ExecutionLane::COUNT

      def initialize(
        handler:,
        lane_index:,
        pull_interval: 1.0,
        execution_lane: Coordinator::Write::Tasks::ExecutionLane.new
      )
        super(
          definition: Coordinator::Shared::Subscriptions::Definition.new(
            set_name: ProcessManagerSet::SET_NAME,
            subscription_name: "coordination-task-executor-lane-#{lane_index}-v2",
            stream_context: "CoordinatorControl",
            stream_name: "CoordinationTask",
            event_types: [ "CoordinationTaskSubmitted" ],
            event_markers: [ execution_lane.marker_for(lane_index) ]
          ),
          handler:,
          pull_interval:
        )
      end
    end
  end
end

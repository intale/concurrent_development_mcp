# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class CoordinationTaskSourceEvent < Dry::Validation::Contract
      def initialize(execution_lane: Coordinator::Write::Tasks::ExecutionLane.new)
        super()
        @execution_lane = execution_lane
      end

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        key.failure("must be a persisted event") unless persisted?(value)
        key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
        key.failure("must be CoordinationTaskSubmitted@1 or @2") unless submitted_schema?(value)
        key.failure("must belong to its CoordinationTask stream") unless matching_task_stream?(value)
        key.failure("must carry its submitted command provenance") unless matching_provenance?(value)
        key.failure("must carry its complete routing markers") unless matching_markers?(value)
        key.failure("must be the root event of its trace") unless value.causation_id.nil?
        key.failure("must carry a pg_eventstore trace correlation ID") unless valid_trace_correlation?(value)
      end

      private

      def persisted?(event)
        !event.stream.nil? && event.stream_revision == 0 && !event.global_position.nil?
      end

      def submitted_schema?(event)
        event.type == "CoordinationTaskSubmitted" && [ 1, 2 ].include?(event.metadata["schema_version"])
      end

      def matching_task_stream?(event)
        stream = event.stream
        task_id = event.data["task_id"]
        return false unless stream && Types::UUID_V7_PATTERN.match?(task_id.to_s)

        stream.context == "CoordinatorControl" &&
          stream.stream_name == "CoordinationTask" &&
          stream.stream_id == task_id
      end

      def matching_provenance?(event)
        task_id = event.data["task_id"]
        command_id = event.data["command_id"]

        expected_policy = "coordination-task/v#{event.metadata['schema_version']}"
        event.metadata["command_id"] == command_id && event.metadata["policy_version"] == expected_policy
      end

      def matching_markers?(event)
        event.markers == [
          "command:#{event.data['command_id']}",
          @execution_lane.marker(event.data["task_id"]),
          "task:#{event.data['task_id']}",
          "tool:#{event.data['tool_name']}"
        ].sort
      end

      def valid_trace_correlation?(event)
        Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
      end
    end
  end
end

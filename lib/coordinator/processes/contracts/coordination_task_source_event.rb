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
        key.failure("must be CoordinationTaskSubmitted@3") unless submitted_schema?(value)
        key.failure("must belong to its CoordinationTask stream") unless matching_task_stream?(value)
        key.failure("must carry its submitted command provenance") unless matching_provenance?(value)
        key.failure("must carry its complete routing markers") unless matching_markers?(value)
        key.failure("must carry schema-correct causation") unless matching_causation?(value)
        key.failure("must carry a pg_eventstore trace correlation ID") unless valid_trace_correlation?(value)
      end

      private

      def persisted?(event)
        !event.stream.nil? && event.stream_revision == 0 && !event.global_position.nil?
      end

      def submitted_schema?(event)
        event.type == "CoordinationTaskSubmitted" && event.metadata["schema_version"] == 3
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
        command_id = event.data["command_id"]
        event.metadata["command_id"] == command_id
      end

      def matching_markers?(event)
        required = [
          "command:#{event.data['command_id']}",
          @execution_lane.marker(event.data["task_id"]),
          "task:#{event.data['task_id']}",
          "tool:#{event.data['tool_name']}"
        ]
        request_markers = event.markers.grep(/\Acompound:command-request:v2\|/)
        request_markers.one? && (required - event.markers).empty?
      end

      def matching_causation?(event)
        Types::UUID_V7_PATTERN.match?(event.causation_id.to_s)
      end

      def valid_trace_correlation?(event)
        Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
      end
    end
  end
end

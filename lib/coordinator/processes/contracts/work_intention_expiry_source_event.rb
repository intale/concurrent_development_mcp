# frozen_string_literal: true

module Coordinator::Processes
  module Contracts
    class WorkIntentionExpirySourceEvent < Dry::Validation::Contract
      SUPPORTED_TYPES = %w[
        ResourceWorkIntentionDeclared
        ResourceWorkIntentionRenewed
      ].freeze

      params do
        required(:event).value(Types.Instance(PgEventstore::Event))
      end

      rule(:event) do
        key.failure("must be a persisted event") unless persisted?(value)
        key.failure("must have a UUIDv7 event ID") unless Types::UUID_V7_PATTERN.match?(value.id)
        key.failure("must be a supported work-intention lifecycle source") unless supported_schema?(value)
        key.failure("must belong to its ResourceWorkIntention stream") unless matching_stream?(value)
        key.failure("must carry command provenance") unless matching_provenance?(value)
        key.failure("must carry its work-intention routing markers") unless matching_markers?(value)
        key.failure("must carry a pg_eventstore trace correlation ID") unless valid_trace_correlation?(value)
      end

      private

      def persisted?(event)
        event.stream && event.stream_revision && event.stream_revision >= 0 && event.global_position
      end

      def supported_schema?(event)
        SUPPORTED_TYPES.include?(event.type) && event.metadata["schema_version"] == 1
      end

      def matching_stream?(event)
        stream = event.stream
        intention_id = event.data["intention_id"]
        return false unless stream && intention_id

        stream.context == "DevelopmentCoordination" &&
          stream.stream_name == "ResourceWorkIntention" &&
          stream.stream_id == intention_id
      end

      def matching_provenance?(event)
        command_id = event.metadata["command_id"]
        # The source policy records its origin; expiry decides against current facts.
        Types::IDENTIFIER_PATTERN.match?(command_id.to_s)
      end

      def matching_markers?(event)
        data = event.data
        markers = event.markers
        required = [
          "command:#{event.metadata['command_id']}",
          "work-intention:#{data['intention_id']}",
          "resource:#{data['resource_id']}"
        ]
        required.all? { markers.include?(_1) } &&
          markers.any? { _1.start_with?("work-intention-set:") } &&
          markers.any? { _1.match?(/role=\d+:resource-exact(?:\||$)/) } &&
          markers.any? { _1.match?(/role=\d+:resource-within(?:\||$)/) }
      end

      def valid_trace_correlation?(event)
        Types::UUID_V7_PATTERN.match?(event.correlation_id.to_s)
      end
    end
  end
end

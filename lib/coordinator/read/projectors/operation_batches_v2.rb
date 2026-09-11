# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class OperationBatchesV2
      PROJECTION = ProjectionDefinition.new(name: "operation_batches", version: 2)

      def initialize(
        contract: Contracts::OperationBatchSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        batches: Repositories::OperationBatches.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @batches = batches
        @processed_events = processed_events
      end

      def call(event)
        validate_source!(event)
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        raise InvalidProjectionSource, "Batch ID does not match source stream" unless payload.batch_id == event.stream.stream_id

        identity = ProjectionEventIdentity.from_event(event)
        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: event.created_at
          )

          @batches.store(event:, payload:)
        end
        nil
      end

      private

      def validate_source!(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?
      end
    end
  end
end

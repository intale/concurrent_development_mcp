# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class OperationBatchesV2
      PROJECTION = ProjectionDefinition.new(name: "operation_batches", version: 2)

      def initialize(
        contract: Contracts::OperationBatchSourceEvent.new,
        pre_semantic_creation: Contracts::PreSemanticOperationBatchCreation.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        batches: Repositories::OperationBatches.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @pre_semantic_creation = pre_semantic_creation
        @schema_registry = schema_registry
        @batches = batches
        @processed_events = processed_events
      end

      def call(event)
        validate_source!(event)
        return acknowledge_pre_semantic_creation(event) if pre_semantic_creation?(event)
        return acknowledge(event) if @batches.pre_semantic?(event.stream.stream_id)

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
            processed_at: Time.now.utc
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

      def pre_semantic_creation?(event)
        @pre_semantic_creation.call(
          event_type: event.type,
          stream_id: event.stream.stream_id,
          data: event.data
        ).success?
      end

      def acknowledge(event)
        identity = ProjectionEventIdentity.from_event(event)
        ApplicationRecord.transaction do
          @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )
        end
        nil
      end

      def acknowledge_pre_semantic_creation(event)
        identity = ProjectionEventIdentity.from_event(event)
        ApplicationRecord.transaction do
          @batches.classify_pre_semantic(event.stream.stream_id)
          @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )
        end
        nil
      end
    end
  end
end

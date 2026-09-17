# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class DecisionPartitionEventReferenceResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        partition_identity_mapper:,
        partition_delta_resolver:,
        target_event_reference_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @partition_identity_mapper = partition_identity_mapper
        @partition_delta_resolver = partition_delta_resolver
        @target_event_reference_resolver = target_event_reference_resolver
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_reference:
      )
        loaded = load(source_event:, source_upper_position:, source_reference:)
        return loaded if loaded.failure?

        referenced_event, payload = loaded.value!
        partition = @partition_identity_mapper.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event:,
          partition: payload.partition
        )
        return partition if partition.failure?

        delta = @partition_delta_resolver.call(
          source_event: referenced_event,
          source_upper_position:
        )
        return delta if delta.failure?

        step_name, event_type = if delta.value!.add
          [ "add-decision-to-partition", "DecisionAddedToPartition" ]
        else
          [ "remove-decision-from-partition", "DecisionRemovedFromPartition" ]
        end
        target = @target_event_reference_resolver.call_in_stream(
          migration_id:,
          source_upper_position:,
          source_event:,
          source_reference:,
          target_stream: StreamReference.new(
            context: "HumanGuidance",
            stream_name: "DecisionPartition",
            stream_id: partition.value!.partition_id
          ),
          target_event_type: event_type,
          target_step_name: step_name
        )
        return target if target.failure?

        Success([ target.value!, payload, partition.value! ].freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      def load(source_event:, source_upper_position:, source_reference:)
        event = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless event && event.id == source_reference.event_id && event.type == source_reference.type &&
            event.global_position <= source_upper_position
          return Failure(inconsistent(source_event, "referenced partition event is absent from the frozen source range"))
        end

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        unless payload.is_a?(Events::DecisionPartitionAdvancedV1)
          return Failure(inconsistent(source_event, "reference does not identify DecisionPartitionAdvanced@1"))
        end

        Success([ event, payload ].freeze)
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, error.message))
      end

      private

      def stream_for(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Decision partition event migration is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

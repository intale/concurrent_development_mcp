# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyWorkIntentionInputContextResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        context_resolver:,
        schema_registry: LegacyEventSchemaRegistry.new
      )
        @event_store = event_store
        @context_resolver = context_resolver
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        attempt_id:,
        lease_set_id:
      )
        reservation = @event_store.read_marked(
          StreamReference.new(
            context: "DevelopmentExecution",
            stream_name: "Attempt",
            stream_id: attempt_id
          ),
          MarkedEventReadCriteria.new(
            event_type: "WriteSetReserved",
            marker: "lease-set:#{lease_set_id}",
            maximum_count: 1,
            direction: :asc
          )
        ).find { _1.global_position <= source_upper_position }
        return Failure(unresolved(source_event, lease_set_id:)) unless reservation

        payload = @schema_registry.load(
          type: reservation.type,
          schema_version: reservation.metadata.fetch("schema_version"),
          data: reservation.data
        )
        unless payload.is_a?(Events::WriteSetReservedV2) &&
            payload.attempt_id == attempt_id && payload.lease_set_id == lease_set_id
          return Failure(unresolved(source_event, lease_set_id:))
        end

        @context_resolver.call(
          migration_id:,
          source_config_name:,
          source_upper_position:,
          source_event: reservation,
          source_payload: payload
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded
        Failure(unresolved(source_event, lease_set_id:))
      end

      private

      def unresolved(source_event, lease_set_id:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Legacy work-intention set #{lease_set_id.inspect} is absent or inconsistent",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

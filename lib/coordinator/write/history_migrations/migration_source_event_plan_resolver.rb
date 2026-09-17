# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationSourceEventPlanResolver
      include Dry::Monads[:result]

      def initialize(event_store:, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_event:, source_event_id:)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorMaintenance",
            stream_name: "HistoryMigrationTargetStreamPlan",
            event_types: [ "HistoryMigrationTargetEventPlanned" ],
            markers: [ "migration-source-event:#{source_event_id}" ],
            maximum_count: 2,
            direction: :asc
          )
        )
        event = events.sole
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        unless payload.is_a?(Events::HistoryMigrationTargetEventPlannedV1) &&
            payload.migration_id == migration_id && payload.source_event_id == source_event_id
          return Failure(unresolved(source_event, source_event_id:))
        end

        Success(payload.target_event)
      rescue Enumerable::SoleItemExpectedError, EventHistoryLimitExceeded,
             KeyError, ArgumentError, Dry::Struct::Error
        Failure(unresolved(source_event, source_event_id:))
      end

      private

      def unresolved(source_event, source_event_id:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Source event #{source_event_id.inspect} has no unique planned target fact",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

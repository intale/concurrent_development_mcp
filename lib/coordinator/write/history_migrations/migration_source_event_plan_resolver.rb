# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationSourceEventPlanResolver
      include Dry::Monads[:result]

      PLAN_SCAN_MAXIMUM = 4_096

      def initialize(event_store:, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(migration_id:, source_event:, source_event_id:)
        entries = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorMaintenance",
            stream_name: "HistoryMigrationTargetStreamPlan",
            event_types: [ "HistoryMigrationTargetEventPlanned" ],
            markers: [ MigrationSourceEventPlanMarker.call(migration_id:, source_event_id:) ],
            maximum_count: PLAN_SCAN_MAXIMUM,
            direction: :asc
          )
        ).map { [ _1, load(_1) ] }
        return Failure(unresolved(source_event, source_event_id:)) unless valid_entries?(
          entries,
          migration_id:,
          source_event_id:
        )

        payload = select_payload(entries, source_event_id:)
        return Failure(unresolved(source_event, source_event_id:)) unless payload

        Success(payload.target_event)
      rescue EventHistoryLimitExceeded, KeyError, ArgumentError, Dry::Struct::Error
        Failure(unresolved(source_event, source_event_id:))
      end

      private

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def valid_entries?(entries, migration_id:, source_event_id:)
        return false if entries.empty?

        source_positions = entries.map { _2.source_global_position }.uniq
        return false unless source_positions.length == 1

        entries.all? do |_event, payload|
          payload.is_a?(Events::HistoryMigrationTargetEventPlannedV1) &&
            payload.migration_id == migration_id &&
            payload.source_event_id == source_event_id
        end
      end

      def select_payload(entries, source_event_id:)
        return entries.sole.last if entries.length == 1

        source_position = entries.first.last.source_global_position
        referenced_source = @event_store.read_global_at(source_position)
        return unless referenced_source&.id == source_event_id

        matches = entries.select { _2.target_event.type == referenced_source.type }
        matches.sole.last
      rescue Enumerable::SoleItemExpectedError
        nil
      end

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

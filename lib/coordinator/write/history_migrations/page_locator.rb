# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageLocator
      include Dry::Monads[:result]

      MARKER_PURPOSE = "history-migration-page-range"

      def initialize(
        event_store:,
        marker_codec: Coordinator::Shared::Markers::CodecV2.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @marker_codec = marker_codec
        @schema_registry = schema_registry
      end

      def call(migration_id:, from_position:)
        encoded = marker(migration_id:, from_position:)
        return Failure(encoded.failure) if encoded.failure?

        value = encoded.value!.marker
        events = @event_store.read_global_marked(criteria(value))
        return Failure(error(:page_not_found, migration_id:, from_position:, event_ids: [])) if events.empty?

        event = events.sole
        payload = load(event)
        unless payload.from_position == from_position && payload.page_id == event.stream.stream_id
          return Failure(error(:invalid_page, migration_id:, from_position:, event_ids: [ event.id ]))
        end

        Success(PageLocationV1.new(page_id: payload.page_id, event:, marker: value))
      rescue EventHistoryLimitExceeded
        Failure(error(:duplicate_page, migration_id:, from_position:, event_ids: []))
      rescue KeyError, ArgumentError, Dry::Struct::Error
        Failure(error(:invalid_page, migration_id:, from_position:, event_ids: [ event&.id ].compact))
      end

      def marker(migration_id:, from_position:)
        @marker_codec.call(
          purpose: MARKER_PURPOSE,
          components: [
            { dimension: "migration-id", value: migration_id },
            { dimension: "from-position", value: from_position.to_s }
          ]
        )
      end

      private

      def criteria(marker)
        GlobalMarkedEventReadCriteria.new(
          stream_context: "CoordinatorMaintenance",
          stream_name: "HistoryMigrationPage",
          event_types: [ "HistoryMigrationPageSourceRangeSelected" ],
          markers: [ marker ],
          maximum_count: 2,
          direction: :asc
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def error(code, migration_id:, from_position:, event_ids:)
        PageLocationErrorV1.new(
          code:,
          message: {
            page_not_found: "No planned HistoryMigrationPage starts at the application cursor",
            duplicate_page: "More than one HistoryMigrationPage starts at the application cursor",
            invalid_page: "The located HistoryMigrationPage is inconsistent with its selector"
          }.fetch(code),
          migration_id:,
          from_position:,
          event_ids:
        )
      end
    end
  end
end

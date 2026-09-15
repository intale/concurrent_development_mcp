# frozen_string_literal: true

module Coordinator::Processes
  module HistoryMigrations
    class SourceBuilder
      def initialize(
        event_store:,
        contract: Contracts::HistoryMigrationSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @contract = contract
        @schema_registry = schema_registry
      end

      def call(event)
        verify!(event)
        persisted = @event_store.read_at(reference(event), event.stream_revision)
        unless persisted && persisted.id == event.id && persisted.global_position == event.global_position
          raise InvalidSourceEvent, "HistoryMigration source is not the exact persisted event"
        end

        SourceV1.new(event: persisted, payload: load(persisted))
      rescue Dry::Struct::Error,
             Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise InvalidSourceEvent, error.message
      end

      private

      def verify!(event)
        result = @contract.call(event:)
        raise InvalidSourceEvent, result.errors.to_h.inspect if result.failure?
      end

      def reference(event)
        Coordinator::Write::StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end
    end
  end
end

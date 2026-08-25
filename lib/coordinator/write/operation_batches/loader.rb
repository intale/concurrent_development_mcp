# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class Loader
      def initialize(event_store:, schema_registry: EventSchemaRegistry.new, stream_factory: StreamFactory.new)
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
      end

      def call(batch_id)
        physical_events = @event_store.read(
          @stream_factory.operation_batch(batch_id),
          EventQueries::OPERATION_BATCH_HISTORY
        )
        payloads = physical_events.map do |event|
          @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          )
        end
        SnapshotV1.new(state: State.reduce(payloads), physical_events:)
      end
    end
  end
end

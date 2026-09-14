# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class Loader
      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new,
        stream_factory: StreamFactory.new,
        item_builder: ItemBuilder.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @item_builder = item_builder
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
        items = payloads.each_with_index.filter_map do |payload, index|
          next unless payload.is_a?(Events::OperationBatchItemEnqueuedV1)

          @item_builder.call(event: physical_events.fetch(index), payload:)
        end
        creation_index = payloads.index { _1.is_a?(Events::OperationBatchCreatedV2) }
        page_size = creation_index && physical_events.fetch(creation_index).metadata.fetch("page_size")

        SnapshotV1.new(state: State.reduce(payloads, items:, page_size:), physical_events:)
      end
    end
  end
end

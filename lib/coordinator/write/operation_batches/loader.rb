# frozen_string_literal: true

module Coordinator::Write
  module OperationBatches
    class Loader
      ITEM_EVENT_TYPES = %w[
        OperationBatchItemEnqueued OperationBatchItemCommandAssigned OperationBatchItemExecutionStarted
        OperationBatchItemRegistrationRejected OperationBatchItemSucceeded OperationBatchItemRejected
        OperationBatchItemCompletionLinked OperationBatchItemFailed
      ].freeze

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
        stream = @stream_factory.operation_batch(batch_id)
        controls = control_events(stream)
        progress = @event_store.read(stream, EventQueries::OPERATION_BATCH_PROGRESS)
        snapshot(controls + progress)
      end

      def control(batch_id)
        snapshot(control_events(@stream_factory.operation_batch(batch_id)))
      end

      def item(batch_id, index)
        stream = @stream_factory.operation_batch(batch_id)
        events = control_events(stream) + item_events(stream, batch_id:, index:, include_input: true)
        payloads = events.map { load(_1) }
        enqueued_index = payloads.index { _1.is_a?(Events::OperationBatchItemEnqueuedV1) }
        assignment = payloads.find { _1.is_a?(Events::OperationBatchItemCommandAssignedV1) }
        items = if enqueued_index
                  payload = payloads.fetch(enqueued_index)
                  [ @item_builder.call(
                    event: events.fetch(enqueued_index), payload:,
                    command_id: assignment&.command_id || payload.command_id
                  ) ]
        else
                  []
        end
        snapshot(events, items:)
      end

      def item_identity(batch_id, index)
        stream = @stream_factory.operation_batch(batch_id)
        events = control_events(stream) + item_events(stream, batch_id:, index:, include_input: false)
        assignment = events.find { _1.type == "OperationBatchItemCommandAssigned" }
        target = events.find { _1.type == "OperationBatchTargetSelected" }
        items = if assignment && target
                  payload = load(assignment)
                  [ ItemIdentityV1.new(
                    index: payload.index, command_id: payload.command_id,
                    tool_name: load(target).target_tool,
                    canonical_input_digest: assignment.metadata.fetch("canonical_input_digest")
                  ) ]
        else
                  []
        end
        snapshot(events, items:)
      end

      private

      def control_events(stream)
        @event_store.read_grouped(stream, EventQueries::OPERATION_BATCH_CONTROL)
      end

      def item_events(stream, batch_id:, index:, include_input:)
        types = include_input ? ITEM_EVENT_TYPES : ITEM_EVENT_TYPES - [ "OperationBatchItemEnqueued" ]
        @event_store.read_marked_types(
          stream,
          MarkedTypesEventReadCriteria.new(
            event_types: types, marker: "batch-item:#{batch_id}:#{index}",
            maximum_count: include_input ? 5 : 4, direction: :asc
          )
        )
      end

      def snapshot(events, items: [], item_count: nil)
        creation = events.find { _1.type == "OperationBatchCreated" }
        manifest = events.find { _1.type == "OperationBatchManifestAccepted" }
        item_count = manifest.metadata.fetch("item_count") if manifest
        SnapshotV1.new(
          state: State.reduce(
            events.map { load(_1) }, items:, item_count:,
            page_size: creation&.metadata&.fetch("page_size")
          ),
          physical_events: events
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data
        )
      end
    end
  end
end

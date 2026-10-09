# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class PartitionStateLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(partition)
        events = @event_store.read(
          @stream_factory.decision_partition(partition.partition_id),
          EventQueries::DECISION_PARTITION_STATE
        )
        active = {}
        events.each do |event|
          payload = load_event(event)
          case payload
          when Events::DecisionAddedToPartitionV1
            head = load_decision_head(payload.decision_id)
            active[payload.decision_id] = head if head
          when Events::DecisionRemovedFromPartitionV1
            active.delete(payload.decision_id)
          end
        end

        DecisionPartitionStateV1.new(
          partition:,
          latest_revision: events.last&.stream_revision,
          active_decisions: active.values.sort_by { _1.decision_id.b },
          latest_event: events.last && event_reference(events.last)
        )
      end

      private

      def load_decision_head(decision_id)
        event = @event_store.read_latest(
          @stream_factory.decision(decision_id),
          LatestEventReadCriteria.new(event_types: %w[DecisionDefinitionCorrected DecisionActivated])
        )
        return unless event

        DecisionHeadV1.new(
          decision_id:,
          decision_revision: event.stream_revision,
          event: event_reference(event)
        )
      end

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def event_reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end
    end
  end
end

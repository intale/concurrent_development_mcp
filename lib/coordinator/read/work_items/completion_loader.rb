# frozen_string_literal: true

module Coordinator::Read
  module WorkItems
    class CompletionLoader
      def initialize(
        event_store:,
        stream_factory: Coordinator::Write::StreamFactory.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(work_item_id, terminal_event_id: nil)
        events = @event_store.read(
          @stream_factory.work_item(work_item_id),
          Coordinator::Write::EventQueries::WORK_ITEM_COMPLETION_FOR_PROJECTION
        )
        terminal_event = events.reverse.find do |event|
          event.type == "WorkItemCompleted" && (!terminal_event_id || event.id == terminal_event_id)
        end
        raise InvalidProjectionSource, "WorkItem is missing its exact completion fact" unless terminal_event

        terminal = load_event(terminal_event)
        selection_event = events.reverse.find { _1.type == "WorkItemCandidateSelected" }
        raise InvalidProjectionSource, "WorkItem completion is missing Candidate selection" unless selection_event

        selection = load_event(selection_event)
        outputs = events.select { _1.type == "WorkItemOutputRecorded" }.map do |event|
          output = load_event(event)
          Coordinator::Write::WorkItemOutputV1.new(kind: output.output_kind, key: output.output_key)
        end
        unless terminal.work_item_id == work_item_id && selection.work_item_id == work_item_id
          raise InvalidProjectionSource, "WorkItem completion facts disagree on work_item_id"
        end

        WorkItemCompletionViewV1.new(
          work_item_id:,
          change_set_id: selection.change_set_id,
          attempt_id: selection.attempt_id,
          candidate_id: selection.candidate_id,
          candidate_event: selection.candidate_event,
          produced_outputs: outputs,
          completed_at: timestamp(terminal_event)
        )
      rescue Dry::Struct::Error, KeyError => error
        raise InvalidProjectionSource, error.message
      end

      private

      def load_event(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def timestamp(event)
        event.created_at.utc.iso8601(6)
      end
    end
  end
end

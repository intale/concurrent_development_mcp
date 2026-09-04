# frozen_string_literal: true

module Coordinator::Write
  module ChangeSetCompletions
    class SourceLoader
      include Dry::Monads[:result]

      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(command)
        stream = source_stream(command)
        event = @event_store.read_at(stream, command.source_event.stream_revision)
        return mismatch unless event && event_reference(event) == command.source_event

        payload = load_event(event)
        return mismatch unless source_matches?(payload, command)

        Success(SourceEvidenceV1.new(event:, reference: command.source_event, payload:))
      rescue EventSchemaRegistry::UnknownSchema, EventSchemaRegistry::SchemaMismatch, Dry::Struct::Error
        mismatch
      end

      private

      def source_stream(command)
        if command.release_set_id
          @stream_factory.release_set(command.release_set_id)
        else
          @stream_factory.work_item(command.source_event.stream_id)
        end
      end

      def source_matches?(payload, command)
        case payload
        when Events::WorkItemCompletedV1
          command.release_set_id.nil? &&
            payload.change_set_id == command.change_set_id &&
            payload.work_item_id == command.source_event.stream_id
        when Events::WorkItemCompletedV2
          command.release_set_id.nil? &&
            payload.work_item_id == command.source_event.stream_id
        when Events::ReleaseSetCompletedV2
          command.release_set_id == payload.release_set_id
        else
          false
        end
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

      def mismatch
        Failure(
          OutcomeError.new(
            code: :change_set_completion_source_mismatch,
            message: "Exact ChangeSet completion source is absent or does not match the command",
            details: {}
          )
        )
      end
    end
  end
end

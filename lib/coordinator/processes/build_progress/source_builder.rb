# frozen_string_literal: true

module Coordinator::Processes
  module BuildProgress
    class SourceBuilder
      def initialize(
        event_store:,
        contract: Contracts::BuildProgressSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        stream_factory: Coordinator::Write::StreamFactory.new,
        release_history_loader: Coordinator::Write::ReleaseSets::HistoryLoader.new(event_store:)
      )
        @event_store = event_store
        @contract = contract
        @schema_registry = schema_registry
        @stream_factory = stream_factory
        @release_history_loader = release_history_loader
      end

      def call(event)
        validation = @contract.call(event:)
        raise BuildProgressProcessRejected, validation.errors.to_h.inspect if validation.failure?

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        SourceV1.new(
          event:,
          reference: Coordinator::Write::EventReference.new(
            event_id: event.id,
            type: event.type,
            stream_context: event.stream.context,
            stream_name: event.stream.stream_name,
            stream_id: event.stream.stream_id,
            stream_revision: event.stream_revision
          ),
          payload:,
          change_set_id: change_set_id(payload, event)
        )
      rescue Dry::Struct::Error, Coordinator::Write::EventSchemaRegistry::UnknownSchema,
             Coordinator::Write::EventSchemaRegistry::SchemaMismatch => error
        raise BuildProgressProcessRejected, error.message
      end

      private

      def change_set_id(payload, event)
        if payload.is_a?(Coordinator::Write::Events::ReleaseSetCompletedV2)
          return @release_history_loader.call(payload.release_set_id).preparation.payload.change_set_id
        end
        return payload.change_set_id unless payload.is_a?(Coordinator::Write::Events::WorkItemCompletedV2)

        selection = @event_store.read(
          @stream_factory.work_item(event.stream.stream_id),
          Coordinator::Write::EventQueries::WORK_ITEM_LATEST_CANDIDATE_SELECTION
        ).first
        raise BuildProgressProcessRejected, "WorkItemCompleted has no Candidate selection" unless selection

        @schema_registry.load(
          type: selection.type,
          schema_version: selection.metadata.fetch("schema_version"),
          data: selection.data
        ).change_set_id
      end
    end
  end
end

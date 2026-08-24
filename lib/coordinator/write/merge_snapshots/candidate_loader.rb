# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class CandidateLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new,
        contract: Contracts::MergeSnapshotCandidateHistory.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
        @contract = contract
      end

      def call(requested)
        events = @event_store.read(
          @stream_factory.candidate(requested.candidate_id),
          EventQueries::CANDIDATE_FOR_MERGE_SNAPSHOT
        )
        candidate_event = events.find { _1.type == "CandidateSubmitted" }
        manifest_event = events.find { _1.type == "CandidateChangeManifestCaptured" }
        history = CandidateHistoryV1.new(
          requested:,
          candidate: candidate_event && load_event(candidate_event),
          manifest: manifest_event && load_event(manifest_event),
          candidate_event: candidate_event && event_reference(candidate_event),
          manifest_event: manifest_event && event_reference(manifest_event)
        )
        validation = @contract.call(history:)
        return history if validation.success?

        raise InvalidMergeSnapshotCandidateHistory, validation.errors.to_h.inspect
      end

      private

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

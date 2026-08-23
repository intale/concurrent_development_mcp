# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ExactEventLoader
      def initialize(event_store:, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(reference)
        event = @event_store.read_at(
          StreamReference.new(
            context: reference.stream_context,
            stream_name: reference.stream_name,
            stream_id: reference.stream_id
          ),
          reference.stream_revision
        )
        unless event && event_reference(event) == reference
          raise InvalidHistory.new(
            reason: "referenced_event_not_found",
            evidence: { reference: reference.to_h }
          )
        end

        PersistedEventV1.new(
          event:,
          payload: @schema_registry.load(
            type: event.type,
            schema_version: event.metadata.fetch("schema_version"),
            data: event.data
          ),
          reference:
        )
      end

      private

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

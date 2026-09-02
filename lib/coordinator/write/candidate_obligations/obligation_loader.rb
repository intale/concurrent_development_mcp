# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ObligationLoader
      def initialize(
        event_store:,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def find(natural_key)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "DevelopmentIntegration",
            stream_name: "VerificationObligation",
            event_types: [ "VerificationObligationCreated" ],
            markers: [ natural_key.marker ],
            maximum_count: 2,
            direction: :asc
          )
        )
        if events.length > 1
          raise InvalidHistory.new(
            reason: "obligation_natural_key_duplicated",
            evidence: { marker: natural_key.marker, event_ids: events.map(&:id) }
          )
        end
        event = events.first
        return unless event

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        reference = event_reference(event)
        valid = payload.is_a?(Events::VerificationObligationCreatedV1) &&
                event.stream_revision == 0 &&
                payload.obligation_id == event.stream.stream_id &&
                reference.type == "VerificationObligationCreated" &&
                reference.stream_context == "DevelopmentIntegration" &&
                reference.stream_name == "VerificationObligation" &&
                reference.stream_id == payload.obligation_id &&
                event.markers.include?(natural_key.marker)
        unless valid
          raise InvalidHistory.new(
            reason: "obligation_replay_invalid",
            evidence: {
              obligation_id: event.stream.stream_id,
              event_id: event.id
            }
          )
        end

        PersistedEventV1.new(event:, payload:, reference:)
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

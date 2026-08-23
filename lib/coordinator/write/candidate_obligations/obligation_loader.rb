# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ObligationLoader
      def initialize(
        event_store:,
        stream_factory: StreamFactory.new,
        schema_registry: EventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(identity)
        event = @event_store.read(
          @stream_factory.verification_obligation(identity.obligation_id),
          EventQueries::VERIFICATION_OBLIGATION_CREATION
        ).first
        return unless event

        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        reference = event_reference(event)
        valid = payload.is_a?(Events::VerificationObligationCreatedV1) &&
                event.stream_revision == 0 &&
                payload.obligation_id == identity.obligation_id &&
                reference.type == "VerificationObligationCreated" &&
                reference.stream_context == "DevelopmentIntegration" &&
                reference.stream_name == "VerificationObligation" &&
                reference.stream_id == identity.obligation_id
        unless valid
          raise InvalidHistory.new(
            reason: "obligation_replay_invalid",
            evidence: {
              obligation_id: identity.obligation_id,
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

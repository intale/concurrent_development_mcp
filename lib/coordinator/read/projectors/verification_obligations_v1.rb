# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class VerificationObligationsV1
      PROJECTION = ProjectionDefinition.new(name: "verification_obligations", version: 1)

      def initialize(
        contract: Contracts::VerificationObligationSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        obligations: Repositories::VerificationObligations.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @obligations = obligations
        @processed_events = processed_events
      end

      def call(event)
        payload = load_payload(event)
        verify_stream_identity!(event, payload)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: Time.now.utc
          )

          @obligations.store_creation(event:, obligation: payload)
        end

        nil
      end

      private

      def load_payload(event)
        result = @contract.call(
          event_type: event.type,
          schema_version: event.metadata["schema_version"],
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision,
          global_position: event.global_position,
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, payload)
        return if event.stream.stream_id == payload.obligation_id

        raise InvalidProjectionSource, "VerificationObligation identity does not match its source stream"
      end
    end
  end
end

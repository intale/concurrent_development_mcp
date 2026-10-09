# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class DecisionInterpretationsV1
      PROJECTION = ProjectionDefinition.new(name: "decision_interpretations", version: 1)

      def initialize(
        contract: Contracts::DecisionInterpretationSourceEvent.new,
        source_loader:,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        interpretations: Repositories::DecisionInterpretations.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @source_loader = source_loader
        @schema_registry = schema_registry
        @interpretations = interpretations
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
            processed_at: event.created_at
          )

          project(event, payload)
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
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, payload)
        return if event.stream.stream_id == payload.interpretation_id

        raise InvalidProjectionSource, "interpretation identity does not match its source stream"
      end

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::DecisionInterpretationProposedV2
          @interpretations.store_proposal(event:, source: @source_loader.call(event, payload))
        when Coordinator::Write::Events::DecisionClarificationRequiredV2
          @interpretations.require_clarification(event:, clarification: payload)
        when Coordinator::Write::Events::DecisionInterpretationAcceptedV2
          @interpretations.accept(event:, acceptance: payload)
        when Coordinator::Write::Events::DecisionInterpretationRejectedV2
          @interpretations.reject(event:, rejection: payload)
        end
      end
    end
  end
end

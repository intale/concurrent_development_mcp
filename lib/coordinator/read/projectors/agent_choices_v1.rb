# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class AgentChoicesV1
      PROJECTION = ProjectionDefinition.new(name: "agent_choices", version: 1)

      def initialize(
        contract: Contracts::AgentChoiceSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        choices: Repositories::AgentChoices.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @choices = choices
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
          command_id: event.metadata["command_id"],
          actor_kind: event.metadata["actor_kind"],
          actor_id: event.metadata["actor_id"],
          recorded_by: event.metadata["recorded_by"],
          policy_version: event.metadata["policy_version"],
          context_digest: event.metadata["context_digest"]
        )
        raise InvalidProjectionSource, result.errors.to_h.inspect if result.failure?

        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def verify_stream_identity!(event, payload)
        return if event.stream.stream_id == payload.choice_id

        raise InvalidProjectionSource, "AgentChoice identity does not match its source stream"
      end

      def project(event, payload)
        case payload
        when Coordinator::Write::Events::AgentChoiceRecordedV1,
             Coordinator::Write::Events::AgentChoiceRecordedV2
          @choices.store_recorded(event:, choice: payload)
        when Coordinator::Write::Events::AgentChoiceAcceptedV1,
             Coordinator::Write::Events::AgentChoiceAcceptedV2
          @choices.accept(event:, acceptance: payload)
        end
      end
    end
  end
end

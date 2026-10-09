# frozen_string_literal: true

module Coordinator::Read
  module Projectors
    class UserUtterancesV1
      PROJECTION = ProjectionDefinition.new(name: "user_utterances", version: 1)

      def initialize(
        contract: Contracts::GuidanceSourceEvent.new,
        schema_registry: Coordinator::Write::EventSchemaRegistry.new,
        utterances: Repositories::UserUtterances.new,
        processed_events: Repositories::ProcessedProjectionEvents.new
      )
        @contract = contract
        @schema_registry = schema_registry
        @utterances = utterances
        @processed_events = processed_events
      end

      def call(event)
        fact = load_fact(event)
        verify_stream_identity!(event, fact)
        identity = ProjectionEventIdentity.from_event(event)

        ApplicationRecord.transaction do
          next unless @processed_events.claim(
            definition: PROJECTION,
            identity:,
            processed_at: event.created_at
          )

          project(event, fact)
        end

        nil
      end

      private

      def load_fact(event)
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

      def verify_stream_identity!(event, fact)
        return if event.stream.stream_id == fact.conversation_id

        raise InvalidProjectionSource, "utterance conversation does not match its source stream"
      end

      def project(event, fact)
        case fact
        when Coordinator::Write::Events::UserUtteranceRecordedV2,
             Coordinator::Write::Events::UserUtteranceForwardedByAgentV2
          @utterances.store(event:, utterance: fact)
        when Coordinator::Write::Events::GuidanceMessageAnchoredV1
          @utterances.add_anchor(event:, anchor: fact)
        end
      end
    end
  end
end

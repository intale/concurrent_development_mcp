# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class GuidanceMessageIdentityResolver
      include Dry::Monads[:result]

      SOURCE_TYPES = [
        Events::UserUtteranceRecordedV1,
        Events::UserUtteranceForwardedByAgentV1
      ].freeze

      def initialize(event_store:, schema_registry: LegacyEventSchemaRegistry.new)
        @event_store = event_store
        @schema_registry = schema_registry
      end

      def call(source_event:, source_upper_position:, source_reference:, source_message_id:)
        persisted = @event_store.read_at(stream_for(source_reference), source_reference.stream_revision)
        unless valid_reference?(persisted, source_reference:, source_upper_position:)
          return Failure(inconsistent(source_event, "guidance-message reference is absent"))
        end

        payload = load_payload(persisted)
        unless SOURCE_TYPES.any? { payload.is_a?(_1) } &&
            payload.message_id == source_message_id &&
            payload.conversation_id == persisted.stream.stream_id
          return Failure(inconsistent(source_event, "guidance-message reference is inconsistent"))
        end

        Success(
          GuidanceMessageIdentityV1.new(
            source_message: payload,
            source_event: persisted,
            target_message_id: persisted.id
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error => error
        Failure(inconsistent(source_event, "guidance-message reference is invalid: #{error.message}"))
      end

      private

      def valid_reference?(event, source_reference:, source_upper_position:)
        event &&
          event.id == source_reference.event_id &&
          event.type == source_reference.type &&
          event.global_position <= source_upper_position
      end

      def load_payload(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def stream_for(reference)
        StreamReference.new(
          context: reference.stream_context,
          stream_name: reference.stream_name,
          stream_id: reference.stream_id
        )
      end

      def inconsistent(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Interpretation source is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

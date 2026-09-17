# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PostRemodelGuidanceIdentityResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        stream_identity_allocator:,
        schema_registry: SourceEventSchemaRegistry.new
      )
        @event_store = event_store
        @stream_identity_allocator = stream_identity_allocator
        @schema_registry = schema_registry
      end

      def call(
        migration_id:,
        source_config_name:,
        source_upper_position:,
        source_event:,
        source_conversation_id:,
        source_message_id:
      )
        message_event = source_message_event(
          source_event,
          source_upper_position:,
          source_message_id:
        )
        payload = message_event && load(message_event)
        valid = message_event && payload.is_a?(Events::UserUtteranceForwardedByAgentV2) &&
                payload.message_id == source_message_id &&
                payload.conversation_id == source_conversation_id &&
                message_event.stream.stream_id == source_conversation_id
        return Failure(invalid(source_event, "guidance message is absent or inconsistent")) unless valid

        root = @event_store.read_at(stream_for(message_event), 0)
        unless root && root.global_position <= source_upper_position
          return Failure(invalid(source_event, "guidance conversation root is absent"))
        end

        conversation = allocate(
          migration_id:,
          source_config_name:,
          source_event: root,
          target_stream_name: "Conversation",
          identity_role: "conversation"
        )
        return conversation if conversation.failure?

        message = allocate(
          migration_id:,
          source_config_name:,
          source_event: message_event,
          target_stream_name: "GuidanceMessageIdentity",
          identity_role: "guidance-message:#{message_event.id}"
        )
        return message if message.failure?

        Success(
          PostRemodelGuidanceIdentityV1.new(
            target_stream: conversation.value!.target_stream,
            message_id: message.value!.target_stream.stream_id
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error,
             EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      private

      def source_message_event(source_event, source_upper_position:, source_message_id:)
        if source_event.type == "UserUtteranceForwardedByAgent"
          return source_event if source_event.global_position <= source_upper_position
        end

        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "HumanGuidance",
            stream_name: "Conversation",
            event_types: [ "UserUtteranceForwardedByAgent" ],
            markers: [ "message:#{source_message_id}" ],
            maximum_count: 2,
            direction: :asc,
            to_position: source_upper_position
          )
        )
        events.sole
      rescue Enumerable::SoleItemExpectedError
        nil
      end

      def allocate(
        migration_id:,
        source_config_name:,
        source_event:,
        target_stream_name:,
        identity_role:
      )
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "HumanGuidance",
          target_stream_name:,
          identity_role:
        )
      end

      def stream_for(event)
        StreamReference.new(
          context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id
        )
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Post-remodel guidance identity is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

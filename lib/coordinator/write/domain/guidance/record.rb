# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module Guidance
      class Record
        include Dry::Monads[:result]

        def initialize(stream_factory: StreamFactory.new)
          @stream_factory = stream_factory
        end

        def call(state:, command:, occurred_at:)
          return duplicate_failure(command.message_id) unless state.absent?

          stream = @stream_factory.conversation(command.conversation_id)
          events = [ build_event(command:) ] + anchor_events(command)
          Success(EventPlan.new(writes: events.map { EventWrite.new(stream:, event: _1) }))
        end

        private

        def build_event(command:)
          event_class = if command.source == "mcp_client"
            Events::UserUtteranceRecordedV2
          else
            Events::UserUtteranceForwardedByAgentV2
          end

          event_class.new(
            conversation_id: command.conversation_id,
            message_id: command.message_id,
            source: command.source == "mcp_client" ? "user" : command.source,
            text: command.text,
          )
        end

        def anchor_events(command)
          anchors = command.anchors.repository_ids.map { [ "repository", _1 ] }
          anchors << [ "change_set", command.anchors.change_set_id ] if command.anchors.change_set_id
          anchors << [ "work_item", command.anchors.work_item_id ] if command.anchors.work_item_id
          anchors << [ "attempt", command.anchors.attempt_id ] if command.anchors.attempt_id
          anchors.map do |kind, id|
            Events::GuidanceMessageAnchoredV1.new(
              conversation_id: command.conversation_id,
              message_id: command.message_id,
              anchor_kind: kind,
              anchor_id: id
            )
          end
        end

        def duplicate_failure(message_id)
          Failure(
            OutcomeError.new(
              code: :message_already_recorded,
              message: "Guidance message is already recorded",
              details: { message_id: }
            )
          )
        end
      end
    end
  end
end

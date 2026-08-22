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

          Success(
            EventPlan.new(
              writes: [
                EventWrite.new(
                  stream: @stream_factory.conversation(command.conversation_id),
                  event: build_event(command:, occurred_at:)
                )
              ]
            )
          )
        end

        private

        def build_event(command:, occurred_at:)
          event_class = if command.source == "mcp_client"
            Events::UserUtteranceRecordedV1
          else
            Events::UserUtteranceForwardedByAgentV1
          end

          event_class.new(
            message_id: command.message_id,
            conversation_id: command.conversation_id,
            text: command.text,
            source: command.source,
            anchors: command.anchors,
            recorded_at: occurred_at
          )
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

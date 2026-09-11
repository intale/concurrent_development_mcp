# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class UserUtterances < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "user-utterances-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "HumanGuidance",
            stream_name: "Conversation"
          )
        ],
        event_types: Contracts::GuidanceSourceEvent::EVENT_TYPES
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

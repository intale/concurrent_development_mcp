# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class AgentChoices < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "agent-choices-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "AgentGovernance",
            stream_name: "AgentChoice"
          )
        ],
        event_types: %w[AgentChoiceRecorded AgentChoiceAccepted]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

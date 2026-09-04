# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class AgentChoiceImpacts < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "agent-choice-impacts-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "AgentGovernance",
            stream_name: "AgentChoiceImpact"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "AgentGovernance",
            stream_name: "AgentChoice"
          )
        ],
        event_types: %w[
          AgentChoiceImpactAssessmentRecorded
          AgentChoiceImpactSourceLinked
          AgentChoiceInvalidatedByDecision
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

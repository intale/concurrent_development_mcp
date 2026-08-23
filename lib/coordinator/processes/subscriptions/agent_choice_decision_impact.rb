# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class AgentChoiceDecisionImpact < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "agent-choice-decision-impact-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "HumanGuidance",
            stream_name: "Decision"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "AgentGovernance",
            stream_name: "AgentChoice"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "AgentGovernance",
            stream_name: "AgentChoiceImpactScan"
          )
        ],
        event_types: %w[
          DecisionActivated
          DecisionDefinitionCorrected
          AgentChoiceAccepted
          AgentChoiceImpactScanStarted
          AgentChoiceImpactScanProgressed
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class DecisionGovernance < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "decision-governance-v1",
        streams: %w[Decision DecisionSlot DecisionPartition].map do |stream_name|
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "HumanGuidance",
            stream_name:
          )
        end,
        event_types: Contracts::DecisionGovernanceSourceEvent::EVENT_TYPES
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class DecisionInterpretations < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "decision-interpretations-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "HumanGuidance",
            stream_name: "Interpretation"
          )
        ],
        event_types: Contracts::DecisionInterpretationSourceEvent::EVENT_TYPES
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class Skills < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "skills-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "AgentKnowledge",
            stream_name: "Skill"
          )
        ],
        event_types: [ "SkillRevisionPublished" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

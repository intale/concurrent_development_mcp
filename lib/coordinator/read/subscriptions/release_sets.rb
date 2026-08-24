# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class ReleaseSets < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "release-sets-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "ReleaseSet"
          )
        ],
        event_types: [ "ReleaseSetPrepared" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

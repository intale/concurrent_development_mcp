# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class Resources < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "resources-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentCoordination",
            stream_name: "Resource"
          )
        ],
        event_types: %w[ResourceRegistered ResourceBound ResourceUnbound]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class CoordContext < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "coord-context-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(context: "DevelopmentPlanning", stream_name: "ChangeSet"),
          Coordinator::Shared::Subscriptions::StreamFilter.new(context: "DevelopmentExecution", stream_name: "WorkItem"),
          Coordinator::Shared::Subscriptions::StreamFilter.new(context: "DevelopmentExecution", stream_name: "Attempt")
        ],
        event_types: Contracts::CoordContextSourceEvent::EVENT_STREAMS.keys
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator
  module Subscriptions
    class CoordContext < Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "coord-context-v1",
        streams: [
          StreamFilter.new(context: "DevelopmentPlanning", stream_name: "ChangeSet"),
          StreamFilter.new(context: "DevelopmentExecution", stream_name: "WorkItem"),
          StreamFilter.new(context: "DevelopmentExecution", stream_name: "Attempt")
        ],
        event_types: Contracts::CoordContextSourceEvent::EVENT_STREAMS.keys
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

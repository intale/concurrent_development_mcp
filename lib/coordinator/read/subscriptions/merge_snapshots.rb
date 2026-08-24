# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class MergeSnapshots < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "merge-snapshots-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "MergeSnapshot"
          )
        ],
        event_types: [ "MergeSnapshotRegistered" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

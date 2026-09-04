# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class MergeSnapshotVerification < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "merge-snapshot-verification-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "MergeVerification"
          )
        ],
        event_types: [ "MergeSnapshotVerificationSubmitted" ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

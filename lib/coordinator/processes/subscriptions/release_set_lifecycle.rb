# frozen_string_literal: true

module Coordinator::Processes
  module Subscriptions
    class ReleaseSetLifecycle < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ProcessDefinition.new(
        set_name: ProcessManagerSet::SET_NAME,
        subscription_name: "release-set-lifecycle-v1",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "ReleaseSet"
          )
        ],
        event_types: %w[
          RepositoryIntegrationRecorded
          ReleaseSetVerificationRecorded
          ReleaseSetActivated
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

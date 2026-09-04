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
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "MergeAuthorization"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentIntegration",
            stream_name: "MergeVerification"
          )
        ],
        event_types: [
          "MergeSnapshotRegistered",
          "MergeSnapshotVerificationSubmitted",
          "MergeSnapshotVerificationAssigned",
          "MergeSnapshotVerificationSelected",
          "MergeSnapshotVerified",
          "MergeAuthorizationGranted",
          "MergeAuthorizationDenied",
          "MergeObserved",
          "MergeObservationAuthorizationLinked"
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

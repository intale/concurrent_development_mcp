# frozen_string_literal: true

module Coordinator::Read
  module Subscriptions
    class DevelopmentArtifacts < Coordinator::Shared::Subscriptions::Registration
      DEFINITION = ReadModelDefinition.new(
        set_name: ReadModelSet::SET_NAME,
        subscription_name: "development-artifacts-v3",
        streams: [
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifact"
          ),
          Coordinator::Shared::Subscriptions::StreamFilter.new(
            context: "DevelopmentMemory",
            stream_name: "DevelopmentArtifactObservation"
          )
        ],
        event_types: %w[
          DevelopmentArtifactCaptured
          DevelopmentArtifactObserved
          DevelopmentArtifactClassificationCorrected
          DevelopmentArtifactRelationDeclared
          DevelopmentArtifactRelationSuperseded
        ]
      )

      def initialize(handler:, pull_interval: 1.0)
        super(definition: DEFINITION, handler:, pull_interval:)
      end
    end
  end
end

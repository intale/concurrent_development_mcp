# frozen_string_literal: true

module Coordinator::Processes::Subscriptions
  class ArtifactRelationStatistics < Coordinator::Shared::Subscriptions::Registration
    DEFINITION = Coordinator::Shared::Subscriptions::Definition.new(
      set_name: ProcessManagerSet::SET_NAME, subscription_name: "artifact-relation-statistics-v1",
      stream_context: "DevelopmentMemory", stream_name: "DevelopmentArtifactRelation",
      event_types: %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded]
    )

    def initialize(handler:, pull_interval: 1.0)
      super(definition: DEFINITION, handler:, pull_interval:)
    end
  end
end

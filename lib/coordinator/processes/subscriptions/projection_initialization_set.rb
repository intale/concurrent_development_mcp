# frozen_string_literal: true

module Coordinator::Processes::Subscriptions
  # Explicit operator process, not an ordinary application subscription set.
  class ProjectionInitializationSet
    SET_NAME = "coordinator-projection-initialization-v1"

    def initialize(event_store:, manager: PgEventstore.subscriptions_manager(subscription_set: SET_NAME))
      @manager = manager
      handler = Coordinator::Processes::ProcessManagers::ProjectionInitialization.new(
        operation: Coordinator::Write::Operations::ExecuteInitializeProjectionFacts.new(event_store:))
      Coordinator::Write::ProjectionInitialization::Definition::ALL.each do |definition|
        register(definition.stream_name.underscore.dasherize, definition.context, definition.stream_name,
          [ definition.source_type ], handler)
      end
      register("artifact-relations", "DevelopmentMemory", "DevelopmentArtifactRelation",
        %w[DevelopmentArtifactRelationDeclared DevelopmentArtifactRelationSuperseded],
        Coordinator::Processes::ProcessManagers::ArtifactRelationStatistics.new(event_store:))
      register("checkpoints", "DevelopmentIntegration", "Candidate", [ "CandidateSubmitted" ],
        Coordinator::Processes::ProcessManagers::CheckpointStatistics.new(event_store:))
    end

    def start
      @manager.start!
    end

    private

    def register(name, context, stream_name, event_types, handler)
      definition = Coordinator::Shared::Subscriptions::Definition.new(set_name: SET_NAME,
        subscription_name: "initialize-#{name}-v1", stream_context: context, stream_name:, event_types:)
      Coordinator::Shared::Subscriptions::Registration.new(definition:, handler:).register(@manager)
    end
  end
end

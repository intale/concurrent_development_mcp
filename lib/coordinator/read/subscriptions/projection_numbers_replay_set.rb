# frozen_string_literal: true

module Coordinator::Read::Subscriptions
  # Explicit operator replay; never part of the ordinary Read subscription set.
  class ProjectionNumbersReplaySet
    SET_NAME = "coordinator-projection-numbers-replay-v1"
    ARTIFACT_RELATIONS = ReadModelDefinition.new(
      set_name: SET_NAME,
      subscription_name: "replay-artifact-relation-numbers-v1",
      streams: [ Coordinator::Shared::Subscriptions::StreamFilter.new(
        context: "DevelopmentMemory", stream_name: "DevelopmentArtifactRelationStatistics") ],
      event_types: [ "DevelopmentArtifactRelationsNumberChanged" ]
    )
    CHECKPOINTS = ReadModelDefinition.new(
      set_name: SET_NAME,
      subscription_name: "replay-checkpoint-numbers-v1",
      streams: [ Coordinator::Shared::Subscriptions::StreamFilter.new(
        context: "DevelopmentIntegration", stream_name: "CheckpointStatistics") ],
      event_types: [ "ChangeSetRepositoryCheckpointNumberChanged" ]
    )

    def initialize(artifact_handler:, checkpoint_handler:,
      manager: PgEventstore.subscriptions_manager(subscription_set: SET_NAME))
      @manager = manager
      BatchRegistration.new(definition: ARTIFACT_RELATIONS, handler: artifact_handler).register(@manager)
      BatchRegistration.new(definition: CHECKPOINTS, handler: checkpoint_handler).register(@manager)
    end

    def start
      @manager.start!
    end
  end
end

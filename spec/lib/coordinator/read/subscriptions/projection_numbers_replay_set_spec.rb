# frozen_string_literal: true

RSpec.describe Coordinator::Read::Subscriptions::ProjectionNumbersReplaySet do
  it "registers two precise native batch consumers on one separate real SDK manager without starting it" do
    manager = PgEventstore.subscriptions_manager(subscription_set: described_class::SET_NAME)

    described_class.new(
      manager:,
      artifact_handler: Coordinator::Container["projectors.development_artifacts_v1"],
      checkpoint_handler: Coordinator::Container["projectors.coord_context_v1"]
    )

    expect(manager.subscriptions.map(&:name)).to eq(
      %w[replay-artifact-relation-numbers-v1 replay-checkpoint-numbers-v1]
    )
    expect(described_class::ARTIFACT_RELATIONS.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentMemory", stream_name: "DevelopmentArtifactRelationStatistics" } ],
        event_types: [ "DevelopmentArtifactRelationsNumberChanged" ]
      }
    )
    expect(described_class::CHECKPOINTS.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentIntegration", stream_name: "CheckpointStatistics" } ],
        event_types: [ "ChangeSetRepositoryCheckpointNumberChanged" ]
      }
    )
  end
end

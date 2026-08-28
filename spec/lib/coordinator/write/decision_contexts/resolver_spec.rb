# frozen_string_literal: true

RSpec.describe Coordinator::Write::DecisionContexts::Resolver do
  it "shares the frozen empty-context canonical vector with the available read resolver" do
    context = Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      change_set_id: "CS-golden",
      work_item_id: "W-golden",
      attempt_id: "A-golden",
      phase: "implementation",
      language: "ruby",
      paths: %w[spec/a_spec.rb spec/z_spec.rb],
      environment: nil,
      agent_role: "implementer"
    )
    observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(context).map do |partition|
      Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
        partition:,
        partition_revision: nil,
        event: nil,
        active_decisions: []
      )
    end
    resolution = described_class.new.call(
      context:,
      observations:,
      decisions: [],
      resolved_at: "2026-08-22T12:00:00.000000Z"
    )

    choice_context = Coordinator::Write::DecisionContexts::Builder.new.call(
      context:,
      observations:,
      resolution:,
      resolved_at: "2026-08-22T12:00:00.000000Z"
    )

    expect(choice_context.digest).to eq(
      "sha256:de515474b6eccda722ee2a4b8d5931c702225ca6f723fba14eb7efa9fc04d4c9"
    )
  end
end

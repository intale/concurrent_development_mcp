# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Attempts::State do
  let(:snapshot) do
    Coordinator::Write::RepositorySnapshotV1.new(
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      object_format: "sha1",
      commit_oid: "0123456789abcdef0123456789abcdef01234567"
    )
  end
  let(:definition) do
    [
      Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id: "A-300"),
      Coordinator::Write::Events::AttemptAssignedToWorkItemV1.new(
        attempt_id: "A-300", change_set_id: "CS-100", work_item_id: "W-200"
      ),
      Coordinator::Write::Events::AttemptAssignedToAgentV1.new(attempt_id: "A-300", agent_id: "agent-a"),
      Coordinator::Write::Events::AttemptBaseSnapshotRecordedV1.new(snapshot.to_h.merge(attempt_id: "A-300")),
      Coordinator::Write::Events::AttemptStartedV2.new(attempt_id: "A-300")
    ]
  end

  it "folds authorization, assignments, repository base and start into immutable active state" do
    state = described_class.reduce(definition)

    expect(state.to_h).to eq(
      attempt_id: "A-300",
      change_set_id: "CS-100",
      work_item_id: "W-200",
      agent_id: "agent-a",
      base_snapshots: [ snapshot.to_h ],
      status: "active",
    )
    expect(state).to be_frozen
  end

  it "applies lean completion without duplicating Candidate or intention state" do
    state = described_class.reduce([
      *definition, Coordinator::Write::Events::AttemptCompletedV2.new(attempt_id: "A-300")
    ])

    expect(state.status).to eq("completed")
    expect(state.to_h.keys).to contain_exactly(
      :attempt_id, :change_set_id, :work_item_id, :agent_id, :base_snapshots, :status
    )
    expect(state.base_snapshots).to eq([ snapshot ])
    expect(state).to be_frozen
  end

  it "applies lean abandonment while retaining the Attempt assignments and base" do
    state = described_class.reduce([
      *definition, Coordinator::Write::Events::AttemptAbandonedV3.new(attempt_id: "A-300", reason: "Hand off")
    ])

    expect(state).to have_attributes(
      status: "abandoned", attempt_id: "A-300", work_item_id: "W-200", agent_id: "agent-a"
    )
    expect(state.base_snapshots).to eq([ snapshot ])
  end
end

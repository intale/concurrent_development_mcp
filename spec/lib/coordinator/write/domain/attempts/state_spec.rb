# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Attempts::State do
  let(:snapshot) do
    Coordinator::Write::RepositorySnapshotV1.new(
      repository_id: "billing",
      object_format: "sha1",
      commit_oid: "0123456789abcdef0123456789abcdef01234567"
    )
  end
  let(:authorized) do
    Coordinator::Write::Events::AttemptAuthorizedV1.new(
      attempt_id: "A-300",
      change_set_id: "CS-100",
      work_item_id: "W-200",
      agent_id: "agent-a",
      base_snapshots: [ snapshot ],
      authorized_at: "2026-08-20T14:20:00.000000Z"
    )
  end
  let(:started) do
    Coordinator::Write::Events::AttemptStartedV1.new(
      attempt_id: "A-300",
      change_set_id: "CS-100",
      work_item_id: "W-200",
      started_at: "2026-08-20T14:20:00.000000Z"
    )
  end

  it "folds authorization and start into immutable active Attempt state" do
    state = described_class.reduce([ authorized, started ])

    expect(state.to_h).to eq(
      attempt_id: "A-300",
      change_set_id: "CS-100",
      work_item_id: "W-200",
      agent_id: "agent-a",
      base_snapshots: [ snapshot.to_h ],
      lease_set_id: nil,
      status: "active"
    )
    expect(state).to be_frozen
  end
end

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
      lease_repository_id: nil,
      lease_policy_version: nil,
      lease_resources: [],
      lease_reserved_at: nil,
      lease_renewed_at: nil,
      lease_expires_at: nil,
      lease_released_at: nil,
      status: "active",
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      completed_at: nil
    )
    expect(state).to be_frozen
  end

  it "folds AttemptCompleted into terminal Candidate attribution" do
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919191",
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-400",
      stream_revision: 0
    )
    completed = Coordinator::Write::Events::AttemptCompletedV1.new(
      attempt_id: "A-300",
      change_set_id: "CS-100",
      work_item_id: "W-200",
      candidate_id: "CAN-400",
      candidate_event:,
      completed_at: "2026-08-20T14:30:00.000000Z"
    )

    state = described_class.reduce([ authorized, started, completed ])

    expect(state).to have_attributes(
      status: "completed",
      selected_candidate_id: "CAN-400",
      selected_candidate_event: candidate_event,
      completed_at: "2026-08-20T14:30:00.000000Z"
    )
  end
end

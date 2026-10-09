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
      selected_candidate_checkpoint_kind: nil
    )
    expect(state).to be_frozen
  end

  it "retains separate Candidate attribution after the lean terminal fact" do
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7, type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration", stream_name: "Candidate",
      stream_id: "CAN-400", stream_revision: 0
    )
    attachment = Coordinator::Write::Events::CandidateAttachedToAttemptV1.new(
      attempt_id: "A-300", change_set_id: "CS-100", work_item_id: "W-200",
      candidate_id: "CAN-400", candidate_event:, repository_id: snapshot.repository_id,
      target_branch: "main", object_format: snapshot.object_format, base_commit_oid: snapshot.commit_oid,
      head_commit_oid: "a" * 40, checkpoint_kind: "final", manifest_digest: "sha256:#{'a' * 64}", build_context_digest: nil,
      attached_at: "2026-08-20T14:30:00.000000Z"
    )
    state = described_class.reduce([
      *definition, attachment, Coordinator::Write::Events::AttemptCompletedV2.new(attempt_id: "A-300")
    ])

    expect(state).to have_attributes(
      status: "completed", selected_candidate_id: "CAN-400",
      selected_candidate_event: candidate_event, selected_candidate_checkpoint_kind: "final"
    )
  end
end

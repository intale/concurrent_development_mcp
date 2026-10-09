# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projections::CoordContextReducer do
  subject(:reducer) { described_class.new }

  it "evicts Candidate checkpoints with Attempt history that leaves the embedded bound" do
    state = bounded_state
    event = Coordinator::Read::AttemptDefinitionViewV1.new(
      attempt_id: "A-current",
      change_set_id: "CS-bounded",
      work_item_id: "W-bounded",
      agent_id: "agent-current",
      base_snapshots: [
        Coordinator::Write::RepositorySnapshotV1.new(
          repository_id: SecureRandom.uuid_v7,
          object_format: "sha1",
          commit_oid: "a" * 40
        )
      ],
      authorization_event: ProjectionEventFactory.build(
        payload: Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id: "A-current"),
        stream: Coordinator::Write::StreamFactory.new.attempt("A-current"),
        stream_revision: 0, global_position: 1001, policy_version: "work-item-acquisition/v1",
        created_at: Time.utc(2026, 9, 17, 12)
      ),
      authorized_at: "2026-09-17T12:00:00.000000Z",
      started_at: "2026-09-17T12:00:01.000000Z"
    )

    updated = reducer.apply(state, event)

    expect(updated.attempts.length).to eq(100)
    expect(updated.candidate_checkpoints.length).to eq(99)
    expect(updated.attempts.map(&:attempt_id)).to include("A-current")
    expect(updated.candidate_checkpoints.map(&:attempt_id)).not_to include("A-000")
  end


  it "retains an older nonterminal Attempt ahead of more recently authorized terminal history" do
    event = Coordinator::Read::AttemptDefinitionViewV1.new(
      attempt_id: "A-old-active", change_set_id: "CS-bounded", work_item_id: "W-bounded", agent_id: "agent-active",
      base_snapshots: [ Coordinator::Write::RepositorySnapshotV1.new(
        repository_id: SecureRandom.uuid_v7, object_format: "sha1", commit_oid: "a" * 40
      ) ],
      authorization_event: ProjectionEventFactory.build(
        payload: Coordinator::Write::Events::AttemptAuthorizedV2.new(attempt_id: "A-old-active"),
        stream: Coordinator::Write::StreamFactory.new.attempt("A-old-active"),
        stream_revision: 0, global_position: 1, policy_version: "work-item-acquisition/v1",
        created_at: Time.utc(2026, 9, 17, 9)
      ),
      authorized_at: "2026-09-17T09:00:00.000000Z", started_at: "2026-09-17T09:00:01.000000Z"
    )

    updated = reducer.apply(bounded_state, event)

    expect(updated.attempts.length).to eq(100)
    expect(updated.attempts.map(&:attempt_id)).to include("A-old-active")
    expect(updated.attempts.map(&:attempt_id)).not_to include("A-000")
    expect(updated.attempts.count { %w[abandoned completed].include?(_1.status) }).to eq(99)
  end

  it "requires the persisted occurrence time for a lean lifecycle fact" do
    event = Coordinator::Write::Events::WorkItemMadeReadyV2.new(
      change_set_id: "CS-bounded", work_item_id: "W-bounded",
      readiness_decision_id: SecureRandom.uuid_v7, reason: "dependencies_satisfied"
    )

    expect { reducer.apply(bounded_state, event) }
      .to raise_error(Coordinator::Read::ProjectionStateError, /persisted Event.created_at/)
  end

  def bounded_state
    initial = Coordinator::Read::Projections::CoordContextStateV1.initial
    timestamp = "2026-09-17T10:00:00.000000Z"
    repository_id = SecureRandom.uuid_v7
    work_item = Coordinator::Read::Projections::CoordContextStateV1::WorkItem.new(
      work_item_id: "W-bounded",
      change_set_id: "CS-bounded",
      repository_id:,
      goal: "Keep embedded coordination bounded",
      acceptance_criteria: [ "Old history is paged separately" ],
      competitive_mode: false,
      status: "ready",
      active_attempt_id: nil,
      active_agent_id: nil,
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      produced_outputs: [],
      created_at: timestamp,
      made_ready_at: timestamp,
      acquired_at: nil,
      selected_at: nil,
      completed_at: nil
    )
    attempts = Array.new(100) { terminal_attempt(_1, repository_id:, timestamp:) }
    checkpoints = Array.new(100) { candidate_checkpoint(_1, repository_id:, timestamp:) }
    Coordinator::Read::Projections::CoordContextStateV1.new(
      initial.attributes.merge(
        work_item_ids: [ "W-bounded" ],
        work_items: [ work_item ],
        attempts:,
        candidate_checkpoints: checkpoints
      )
    )
  end

  def terminal_attempt(index, repository_id:, timestamp:)
    Coordinator::Read::Projections::CoordContextStateV1::Attempt.new(
      attempt_id: format("A-%03d", index),
      change_set_id: "CS-bounded",
      work_item_id: "W-bounded",
      agent_id: "agent-history",
      base_snapshots: [
        Coordinator::Write::RepositorySnapshotV1.new(
          repository_id:,
          object_format: "sha1",
          commit_oid: "a" * 40
        )
      ],
      status: "abandoned",
      authorized_at: (Time.iso8601(timestamp) + index).utc.iso8601(6),
      started_at: timestamp,
      work_intention_set: nil,
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      completed_at: nil,
      abandonment_reason: "Historical checkpoint",
      abandoned_at: timestamp
    )
  end

  def candidate_checkpoint(index, repository_id:, timestamp:)
    candidate_id = format("CAN-%03d", index)
    Coordinator::Read::Projections::CoordContextStateV1::CandidateCheckpoint.new(
      candidate_id:,
      candidate_event: Coordinator::Write::EventReference.new(
        event_id: SecureRandom.uuid_v7,
        type: "CandidateSubmitted",
        stream_context: "DevelopmentIntegration",
        stream_name: "Candidate",
        stream_id: candidate_id,
        stream_revision: 0
      ),
      change_set_id: "CS-bounded",
      work_item_id: "W-bounded",
      attempt_id: format("A-%03d", index),
      repository_id:,
      target_branch: "main",
      object_format: "sha1",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "intermediate",
      manifest_digest: "sha256:#{'c' * 64}",
      build_context_digest: nil,
      attached_at: timestamp
    )
  end
end

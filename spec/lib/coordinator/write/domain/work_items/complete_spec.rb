# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::WorkItems::Complete do
  subject(:decider) { described_class.new }

  let(:completed_at) { "2026-08-25T08:00:00.000000Z" }
  let(:candidate_event) do
    Coordinator::Write::EventReference.new(
      event_id: "01919191-9191-7191-8191-919191919191",
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-1",
      stream_revision: 0
    )
  end
  let(:command) do
    Coordinator::Write::Commands::CompleteWorkItem.new(
      command_id: "cmd-complete-1",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-7"),
      change_set_id: "CS-1",
      work_item_id: "W-1",
      attempt_id: "A-1",
      candidate_id: "CAN-1",
      produced_outputs: [
        Coordinator::Write::WorkItemOutputV1.new(kind: "artifact", key: "billing-gem")
      ]
    )
  end

  it "given exact active authority and a relinquished write set, emits one ordered terminal plan" do
    result = decide

    expect(result).to be_success
    plan = result.value!
    expect(plan.writes.map(&:stream)).to eq([
      streams.work_item("W-1"),
      streams.attempt("A-1"),
      streams.work_item("W-1")
    ])
    expect(plan.events.map(&:class)).to eq([
      Coordinator::Write::Events::WorkItemCandidateSelectedV1,
      Coordinator::Write::Events::AttemptCompletedV1,
      Coordinator::Write::Events::WorkItemCompletedV1
    ])
    expect(plan.events).to all(have_attributes(candidate_event:, candidate_id: "CAN-1"))
    expect(plan.events.last).to have_attributes(
      produced_outputs: command.produced_outputs,
      rule_version: "work-item-completion/v1",
      completed_at:
    )
  end

  it "denies a non-final Candidate and an active unexpired write set" do
    handoff = decide(candidate: candidate(checkpoint_kind: "handoff"))
    active_lease = decide(
      attempt_state: attempt_state(lease_released_at: nil, lease_expires_at: "2026-08-25T08:15:00.000000Z")
    )

    expect(handoff.failure.code).to eq(:candidate_not_final)
    expect(active_lease.failure).to have_attributes(
      code: :write_set_still_active,
      details: include(lease_set_id: lease_set_id, expires_at: "2026-08-25T08:15:00.000000Z")
    )
  end

  it "denies stale ownership, Candidate scope, and already-completed WorkItems" do
    foreign_owner = decide(attempt_state: attempt_state(agent_id: "agent-8"))
    foreign_candidate = decide(candidate: candidate(work_item_id: "W-2"))
    completed = decide(work_item_state: work_item_state(status: "completed"))

    expect(foreign_owner.failure.code).to eq(:attempt_owner_mismatch)
    expect(foreign_candidate.failure.code).to eq(:candidate_scope_mismatch)
    expect(completed.failure.code).to eq(:work_item_already_completed)
  end

  def decide(**overrides)
    decider.call(
      change_set_state: overrides.fetch(:change_set_state, change_set_state),
      work_item_state: overrides.fetch(:work_item_state, work_item_state),
      attempt_state: overrides.fetch(:attempt_state, attempt_state),
      candidate: overrides.fetch(:candidate, candidate),
      candidate_event:,
      command:,
      completed_at:
    )
  end

  def change_set_state
    Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_id: "CS-1",
      goal: "Ship billing",
      status: "active",
      acceptance_criteria: [],
      work_item_ids: [ "W-1" ],
      dependencies: []
    )
  end

  def work_item_state(**overrides)
    Coordinator::Write::Domain::WorkItems::State.new(
      {
        work_item_id: "W-1",
        change_set_id: "CS-1",
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        goal: "Build billing",
        acceptance_criteria: [],
        status: "active",
        active_attempt_id: "A-1",
        active_agent_id: "agent-7",
        selected_candidate_id: nil,
        selected_candidate_event: nil,
        produced_outputs: [],
        completed_at: nil
      }.merge(overrides)
    )
  end

  def attempt_state(**overrides)
    Coordinator::Write::Domain::Attempts::State.new(
      {
        attempt_id: "A-1",
        change_set_id: "CS-1",
        work_item_id: "W-1",
        agent_id: "agent-7",
        base_snapshots: [],
        lease_set_id: lease_set_id,
        lease_repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        lease_resources: [],
        lease_reserved_at: "2026-08-25T07:00:00.000000Z",
        lease_renewed_at: nil,
        lease_expires_at: "2026-08-25T08:15:00.000000Z",
        lease_released_at: "2026-08-25T07:59:00.000000Z",
        status: "active",
        selected_candidate_id: nil,
        selected_candidate_event: nil,
        completed_at: nil
      }.merge(overrides)
    )
  end

  def candidate(**overrides)
    Coordinator::Write::Events::CandidateSubmittedV2.new(
      {
        candidate_id: "CAN-1",
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: "A-1",
        agent_id: "agent-7",
        repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
        target_branch: "main",
        object_format: "sha1",
        base_commit_oid: "a" * 40,
        head_commit_oid: "b" * 40,
        checkpoint_kind: "final",
        lease_set_id: lease_set_id,
        lease_policy_version: Coordinator::Write::LeaseResourceV2::POLICY_VERSION,
        lease_references: [
          Coordinator::Write::LeaseReferenceV2.new(
            resource_id: "01919191-9191-7191-8191-919191919190",
            resource_kind: "file",
            resource_path: "lib/candidate.rb",
            base_blob_oid: "e" * 40,
            lease_id: "01919191-9191-7191-8191-919191919193",
            fencing_token: 1
          )
        ],
        manifest_digest: "sha256:#{"d" * 64}",
        build_context_digest: nil,
        evidence_status: "attributed_unverified",
        submitted_at: "2026-08-25T07:50:00.000000Z"
      }.merge(overrides)
    )
  end

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end

  def lease_set_id
    "01919191-9191-7191-8191-919191919192"
  end
end

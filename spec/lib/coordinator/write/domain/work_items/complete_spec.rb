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

  it "given exact active authority and a current final Candidate, emits one ordered terminal plan" do
    result = decide

    expect(result).to be_success
    plan = result.value!
    expect(plan.writes.map(&:stream)).to eq([
      streams.work_item("W-1"),
      streams.work_item("W-1"),
      streams.attempt("A-1"),
      streams.work_item("W-1")
    ])
    expect(plan.events.map(&:class)).to eq([
      Coordinator::Write::Events::WorkItemCandidateSelectedV2,
      Coordinator::Write::Events::WorkItemOutputRecordedV1,
      Coordinator::Write::Events::AttemptCompletedV2,
      Coordinator::Write::Events::WorkItemCompletedV2
    ])
    expect(plan.events.first).to have_attributes(candidate_event:, candidate_id: "CAN-1")
    expect(plan.events.fetch(1)).to have_attributes(
      work_item_id: "W-1",
      output_kind: "artifact",
      output_key: "billing-gem"
    )
    expect(plan.events.last).to have_attributes(work_item_id: "W-1")
  end

  it "denies a non-final Candidate" do
    handoff = decide(candidate: candidate(checkpoint_kind: "handoff"))

    expect(handoff.failure.code).to eq(:candidate_not_final)
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
        produced_outputs: []
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
        status: "active"
      }.merge(overrides)
    )
  end

  def candidate(**overrides)
    Coordinator::Write::Candidates::StateV2.new(
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
        intention_set_id: intention_set_id,
        manifest_digest: "sha256:#{"d" * 64}",
        build_context_digest: nil,
        manifest: Coordinator::Write::Events::CandidateChangeManifestCapturedV2.new(
          candidate_id: "CAN-1", evidence_revision: 1,
          files: [
            Coordinator::Write::Candidates::ManifestFileV1.new(
              status: "added", old_path: nil, new_path: "lib/candidate.rb",
              old_blob_oid: nil, new_blob_oid: "e" * 40, old_mode: nil, new_mode: "100644"
            )
          ]
        ),
        build_context: nil, submission_event: candidate_event,
        manifest_event: candidate_event.new(type: "CandidateChangeManifestCaptured"),
        build_context_event: nil, surface_id: nil, surface_assignment_event: nil, latest_revision: 8
      }.merge(overrides)
    )
  end

  def streams
    @streams ||= Coordinator::Write::StreamFactory.new
  end

  def intention_set_id
    "01919191-9191-7191-8191-919191919192"
  end
end

# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Attempts::Abandon do
  subject(:decider) { described_class.new }

  let(:id_generator) { Coordinator::Shared::IdGenerator.new }
  let(:abandoned_at) { "2026-08-26T08:30:00.000000Z" }
  let(:future_expires_at) { "2026-08-26T09:00:00.000000Z" }
  let(:snapshot) do
    Coordinator::Write::RepositorySnapshotV1.new(
      repository_id: "billing",
      object_format: "sha1",
      commit_oid: "a" * 40
    )
  end
  let(:command) do
    Coordinator::Write::Commands::AbandonAttempt.new(
      command_id: "CMD-abandon",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-a"),
      change_set_id: "CS-abandon",
      work_item_id: "WI-abandon",
      attempt_id: "ATT-abandon",
      reason: "The agent was interrupted before producing a Candidate."
    )
  end
  let(:work_item_state) { build_work_item_state }

  def build_reference(character:, path:, fencing_token: 1, lease_id: nil)
    Coordinator::Write::LeaseReferenceV1.new(
      lease_id: lease_id || id_generator.uuid_v7,
      resource_key: "repo:billing:file:#{path}",
      resource_key_hash: "sha256:#{character * 64}",
      resource_kind: "file",
      resource_path: path,
      base_blob_oid: nil,
      fencing_token:
    )
  end

  def build_attempt_state(references: [], **overrides)
    attributes = {
      attempt_id: "ATT-abandon",
      change_set_id: "CS-abandon",
      work_item_id: "WI-abandon",
      agent_id: "agent-a",
      base_snapshots: [ snapshot ],
      lease_set_id: references.empty? ? nil : id_generator.uuid_v7,
      lease_repository_id: references.empty? ? nil : "billing",
      lease_policy_version: references.empty? ? nil : "coordinator-resource-key/v1",
      lease_resources: references,
      lease_reserved_at: references.empty? ? nil : "2026-08-26T08:00:00.000000Z",
      lease_renewed_at: nil,
      lease_expires_at: references.empty? ? nil : future_expires_at,
      lease_released_at: nil,
      status: "active",
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      completed_at: nil
    }.merge(overrides)
    Coordinator::Write::Domain::Attempts::State.new(attributes)
  end

  def build_work_item_state(**overrides)
    attributes = {
      work_item_id: "WI-abandon",
      change_set_id: "CS-abandon",
      repository_id: "billing",
      goal: "Implement the abandoned work",
      acceptance_criteria: [ "The WorkItem can be retried" ],
      status: "active",
      active_attempt_id: "ATT-abandon",
      active_agent_id: "agent-a",
      selected_candidate_id: nil,
      selected_candidate_event: nil,
      produced_outputs: [],
      completed_at: nil
    }.merge(overrides)
    Coordinator::Write::Domain::WorkItems::State.new(attributes)
  end

  def build_lease_state(reference:, attempt_state:, **overrides)
    attributes = {
      lease_id: reference.lease_id,
      lease_set_id: attempt_state.lease_set_id,
      resource_key: reference.resource_key,
      resource_key_hash: reference.resource_key_hash,
      resource_kind: reference.resource_kind,
      resource_path: reference.resource_path,
      policy_version: attempt_state.lease_policy_version,
      mode: "exclusive",
      change_set_id: attempt_state.change_set_id,
      work_item_id: attempt_state.work_item_id,
      attempt_id: attempt_state.attempt_id,
      agent_id: attempt_state.agent_id,
      repository_id: attempt_state.lease_repository_id,
      object_format: snapshot.object_format,
      base_commit_oid: snapshot.commit_oid,
      base_blob_oid: reference.base_blob_oid,
      fencing_token: reference.fencing_token,
      acquired_at: "2026-08-26T08:00:00.000000Z",
      renewed_at: nil,
      expires_at: attempt_state.lease_expires_at,
      released_at: nil,
      expired_at: nil
    }.merge(overrides)
    Coordinator::Write::Domain::ResourceLeases::State.new(attributes)
  end

  def observation(reference:, state:)
    Coordinator::Write::CurrentLeaseObservationV1.new(reference:, state:)
  end

  def decide(attempt_state:, observations: [], work_item: work_item_state, submitted_command: command)
    decider.call(
      attempt_state:,
      work_item_state: work_item,
      current_observations: observations,
      command: submitted_command,
      abandoned_at:
    )
  end

  it "requeues an active Attempt that never reserved a write set" do
    result = decide(attempt_state: build_attempt_state)

    expect(result).to be_success
    abandonment, requeue = result.value!.events
    expect(abandonment).to have_attributes(
      lease_set_id: nil,
      released_leases: [],
      untouched_resource_key_hashes: [],
      abandoned_at:
    )
    expect(requeue).to have_attributes(
      attempt_id: command.attempt_id,
      agent_id: command.actor.id,
      reason: command.reason,
      requeued_at: abandoned_at
    )
  end

  it "releases only the exact current fence and leaves a successor fence untouched" do
    current = build_reference(character: "a", path: "app/current.rb")
    superseded = build_reference(character: "b", path: "app/superseded.rb")
    attempt_state = build_attempt_state(references: [ current, superseded ])
    current_state = build_lease_state(reference: current, attempt_state:)
    successor_state = build_lease_state(
      reference: superseded,
      attempt_state:,
      lease_id: id_generator.uuid_v7,
      lease_set_id: id_generator.uuid_v7,
      attempt_id: "ATT-successor",
      agent_id: "agent-b",
      fencing_token: superseded.fencing_token + 1
    )

    result = decide(
      attempt_state:,
      observations: [
        observation(reference: current, state: current_state),
        observation(reference: superseded, state: successor_state)
      ]
    )

    expect(result).to be_success
    release, abandonment, requeue = result.value!.events
    expect(release).to have_attributes(
      lease_id: current.lease_id,
      resource_key_hash: current.resource_key_hash,
      fencing_token: current.fencing_token,
      released_at: abandoned_at
    )
    expect(abandonment.released_leases).to eq([ current ])
    expect(abandonment.untouched_resource_key_hashes).to eq([ superseded.resource_key_hash ])
    expect(requeue).to be_a(Coordinator::Write::Events::WorkItemRequeuedV1)
  end

  it "does not append another release for an already released fence" do
    reference = build_reference(character: "c", path: "app/released.rb")
    attempt_state = build_attempt_state(references: [ reference ])
    released_state = build_lease_state(
      reference:,
      attempt_state:,
      released_at: "2026-08-26T08:20:00.000000Z"
    )

    result = decide(
      attempt_state:,
      observations: [ observation(reference:, state: released_state) ]
    )

    expect(result.value!.events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::AttemptAbandonedV1,
        Coordinator::Write::Events::WorkItemRequeuedV1
      ]
    )
    expect(result.value!.events.first.untouched_resource_key_hashes).to eq([ reference.resource_key_hash ])
  end

  it "does not release a fence whose recorded deadline has elapsed" do
    reference = build_reference(character: "d", path: "app/elapsed.rb")
    elapsed_at = "2026-08-26T08:29:00.000000Z"
    attempt_state = build_attempt_state(
      references: [ reference ],
      lease_expires_at: elapsed_at
    )
    elapsed_state = build_lease_state(reference:, attempt_state:, expires_at: elapsed_at)

    result = decide(
      attempt_state:,
      observations: [ observation(reference:, state: elapsed_state) ]
    )

    expect(result.value!.events.length).to eq(2)
    expect(result.value!.events.first.untouched_resource_key_hashes).to eq([ reference.resource_key_hash ])
  end

  it "denies abandonment after a final Candidate has been attached" do
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: id_generator.uuid_v7,
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-abandon",
      stream_revision: 0
    )
    attempt_state = build_attempt_state(
      selected_candidate_id: "CAN-abandon",
      selected_candidate_event: candidate_event,
      selected_candidate_checkpoint_kind: "final"
    )

    result = decide(attempt_state:)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :attempt_not_active,
      message: "Attempt has a final Candidate and must be completed instead of abandoned"
    )
  end

  it "preserves an intermediate Candidate as history while abandoning its Attempt" do
    candidate_event = Coordinator::Write::EventReference.new(
      event_id: id_generator.uuid_v7,
      type: "CandidateSubmitted",
      stream_context: "DevelopmentIntegration",
      stream_name: "Candidate",
      stream_id: "CAN-intermediate",
      stream_revision: 0
    )
    attempt_state = build_attempt_state(
      selected_candidate_id: "CAN-intermediate",
      selected_candidate_event: candidate_event,
      selected_candidate_checkpoint_kind: "intermediate"
    )

    result = decide(attempt_state:)

    expect(result).to be_success
    expect(result.value!.events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::AttemptAbandonedV1,
        Coordinator::Write::Events::WorkItemRequeuedV1
      ]
    )
  end

  it "denies a scope, owner, or active WorkItem mismatch" do
    attempt_state = build_attempt_state
    wrong_owner = Coordinator::Write::Commands::AbandonAttempt.new(
      command.to_h.merge(actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-b"))
    )

    expect(decide(attempt_state:, submitted_command: wrong_owner).failure.code).to eq(:attempt_owner_mismatch)
    expect(
      decide(
        attempt_state:,
        work_item: build_work_item_state(status: "ready", active_attempt_id: nil, active_agent_id: nil)
      ).failure.code
    ).to eq(:work_item_unavailable)
    expect(
      decide(attempt_state: build_attempt_state(change_set_id: "CS-other")).failure.code
    ).to eq(:attempt_scope_mismatch)
  end
end

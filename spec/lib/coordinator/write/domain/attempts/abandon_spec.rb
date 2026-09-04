# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Attempts::Abandon do
  subject(:abandon) { described_class.new }

  let(:resource) { ResourceLeaseExamples.resource }
  let(:reference) { ResourceLeaseExamples.reference(resource:) }
  let(:attempt_state) do
    ResourceLeaseExamples.active_attempt_state(
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      lease_resources: [ reference ],
      lease_expires_at: ResourceLeaseExamples::EXPIRES_AT
    )
  end
  let(:work_item_state) do
    Coordinator::Write::Domain::WorkItems::State.initial.new(
      work_item_id: "W-LSE-A",
      change_set_id: "CS-LSE",
      repository_id: ResourceLeaseExamples::REPOSITORY_ID,
      goal: "Coordinate the lease",
      acceptance_criteria: [ "The Attempt can be abandoned" ],
      status: "active",
      active_attempt_id: "A-LSE-A",
      active_agent_id: "agent-a"
    )
  end
  let(:command) do
    Coordinator::Write::Commands::AbandonAttempt.new(
      command_id: "cmd-abandon",
      actor: ResourceLeaseExamples.actor,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      reason: "Checkpoint and hand off"
    )
  end

  it "withdraws each active work intention before recording abandonment and requeue facts" do
    result = abandon.call(
      attempt_state:,
      candidate_state: nil,
      work_item_state:,
      set_state: work_intention_set_state,
      member_states: [ work_intention_state ],
      command:,
      abandoned_at: "2026-08-22T10:05:00.000000Z"
    )

    expect(result).to be_success
    withdrawal, abandonment, requeue = result.value!.events
    expect(withdrawal).to eq(
      Coordinator::Write::Events::ResourceWorkIntentionWithdrawnV1.new(
        intention_id: reference.lease_id,
        resource_id: reference.resource_id,
        fencing_token: reference.fencing_token,
        reason: "Checkpoint and hand off"
      )
    )
    expect(abandonment).to eq(
      Coordinator::Write::Events::AttemptAbandonedV3.new(
        attempt_id: "A-LSE-A", reason: "Checkpoint and hand off"
      )
    )
    expect(requeue).to be_a(Coordinator::Write::Events::WorkItemRequeuedV2)
  end

  it "does not emit another terminal fact for an already withdrawn intention" do
    result = abandon.call(
      attempt_state:,
      candidate_state: nil,
      work_item_state:,
      set_state: work_intention_set_state,
      member_states: [ work_intention_state(withdrawn: true) ],
      command:,
      abandoned_at: "2026-08-22T10:05:00.000000Z"
    ).value!

    expect(result.events.map(&:class)).to eq(
      [ Coordinator::Write::Events::AttemptAbandonedV3, Coordinator::Write::Events::WorkItemRequeuedV2 ]
    )
  end

  def work_intention_set_state
    Coordinator::Write::Domain::WorkIntentions::SetState.new(
      set_id: ResourceLeaseExamples::LEASE_SET_ID,
      attempt_id: "A-LSE-A",
      work_item_id: "W-LSE-A",
      change_set_id: "CS-LSE",
      repository_id: ResourceLeaseExamples::REPOSITORY_ID,
      members: [
        Coordinator::Write::WorkIntentionReferenceV1.new(
          intention_id: reference.lease_id,
          resource_id: reference.resource_id
        )
      ]
    )
  end

  def work_intention_state(**overrides)
    Coordinator::Write::Domain::WorkIntentions::State.new(
      {
        intention_id: reference.lease_id,
        set_id: ResourceLeaseExamples::LEASE_SET_ID,
        resource_id: reference.resource_id,
        repository_id: ResourceLeaseExamples::REPOSITORY_ID,
        change_set_id: "CS-LSE",
        work_item_id: "W-LSE-A",
        attempt_id: "A-LSE-A",
        agent_id: "agent-a",
        mode: "shared",
        purpose: "Coordinate the resource",
        context: nil,
        object_format: "sha1",
        base_commit_oid: "a" * 40,
        base_blob_oid: nil,
        fencing_token: reference.fencing_token,
        expires_at: ResourceLeaseExamples::EXPIRES_AT,
        withdrawn: false,
        withdrawal_reason: nil,
        expired: false
      }.merge(overrides)
    )
  end
end

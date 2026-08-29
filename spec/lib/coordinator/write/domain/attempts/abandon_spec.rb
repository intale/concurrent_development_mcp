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

  it "Given a current UUID lease, when abandoning, then releases it and records UUID membership" do
    observation = Coordinator::Write::CurrentLeaseObservationV2.new(
      reference:,
      state: ResourceLeaseExamples.lease_state(resource:, reference:)
    )
    result = abandon.call(
      attempt_state:,
      work_item_state:,
      current_observations: [ observation ],
      command:,
      abandoned_at: "2026-08-22T10:05:00.000000Z"
    )

    expect(result).to be_success
    release, abandonment, requeue = result.value!.events
    expect(release).to be_a(Coordinator::Write::Events::ResourceLeaseReleasedV2)
    expect(abandonment).to be_a(Coordinator::Write::Events::AttemptAbandonedV2)
    expect(abandonment.released_leases).to eq([ reference ])
    expect(abandonment.untouched_resource_ids).to be_empty
    expect(requeue).to be_a(Coordinator::Write::Events::WorkItemRequeuedV1)
  end

  it "Given a successor owns the Resource, when abandoning the old Attempt, then leaves that fence untouched" do
    successor = ResourceLeaseExamples.reference(
      resource:,
      lease_id: "07919191-9191-7191-8191-919191919191",
      fencing_token: 2
    )
    observation = Coordinator::Write::CurrentLeaseObservationV2.new(
      reference:,
      state: ResourceLeaseExamples.lease_state(
        resource:,
        reference: successor,
        fencing_token: 2,
        attempt_id: "A-OTHER",
        agent_id: "agent-b"
      )
    )
    result = abandon.call(
      attempt_state:,
      work_item_state:,
      current_observations: [ observation ],
      command:,
      abandoned_at: "2026-08-22T10:05:00.000000Z"
    ).value!

    expect(result.events.none? { _1.is_a?(Coordinator::Write::Events::ResourceLeaseReleasedV2) }).to be(true)
    expect(result.events.first).to be_a(Coordinator::Write::Events::AttemptAbandonedV2)
    expect(result.events.first.untouched_resource_ids).to eq([ resource.resource_id ])
  end
end

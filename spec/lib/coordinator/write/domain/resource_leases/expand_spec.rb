# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Expand do
  subject(:expand) { described_class.new }

  let(:current_resource) { ResourceLeaseExamples.resource }
  let(:added_resource) do
    ResourceLeaseExamples.resource(
      resource_id: "02919191-9191-7191-8191-919191919191",
      path: "app/models/b.rb",
      base_blob_oid: "c" * 40
    )
  end
  let(:current_reference) { ResourceLeaseExamples.reference(resource: current_resource) }
  let(:attempt_state) do
    ResourceLeaseExamples.active_attempt_state(
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      lease_resources: [ current_reference ],
      lease_expires_at: ResourceLeaseExamples::EXPIRES_AT
    )
  end
  let(:current_observation) do
    Coordinator::Write::CurrentLeaseObservationV2.new(
      reference: current_reference,
      state: ResourceLeaseExamples.lease_state(resource: current_resource, reference: current_reference)
    )
  end
  let(:command) do
    Coordinator::Write::Commands::ExpandWriteSet.new(
      command_id: "cmd-expand",
      actor: ResourceLeaseExamples.actor,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      repository_id: ResourceLeaseExamples::REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ ResourceLeaseExamples.target(added_resource) ]
    )
  end
  let(:requested) do
    Coordinator::Write::RequestedLeaseObservationV2.new(
      prepared_target: Coordinator::Write::PreparedLeaseTargetV1.new(
        target: ResourceLeaseExamples.target(added_resource),
        lease_id: "05919191-9191-7191-8191-919191919191",
        event_id: "06919191-9191-7191-8191-919191919191"
      ),
      resource: added_resource,
      state: Coordinator::Write::Domain::ResourceLeases::State.initial
    )
  end

  it "Given a current set and a free Resource, when expanding, then emits UUID acquisition and membership facts" do
    result = decide

    expect(result).to be_success
    acquisition, expansion = result.value!.events
    expect(acquisition).to be_a(Coordinator::Write::Events::ResourceLeaseAcquiredV2)
    expect(acquisition.resource_id).to eq(added_resource.resource_id)
    expect(expansion).to be_a(Coordinator::Write::Events::WriteSetExpandedV2)
    expect(expansion.added_resources.sole.resource_id).to eq(added_resource.resource_id)
    expect(expansion.resource_count).to eq(2)
  end

  it "Given the submitted current fence is stale, when expanding, then emits no facts" do
    successor = ResourceLeaseExamples.reference(
      resource: current_resource,
      lease_id: "07919191-9191-7191-8191-919191919191",
      fencing_token: 2
    )
    stale = current_observation.new(
      state: ResourceLeaseExamples.lease_state(resource: current_resource, reference: successor, fencing_token: 2)
    )

    result = decide(current_observations: [ stale ])
    expect(result.failure).to have_attributes(code: :lease_set_not_current)
    expect(result.failure.details).to include(resource_id: current_resource.resource_id)
  end

  it "Given another agent owns an ancestor directory, when expanding, then preserves structural exclusion" do
    directory = ResourceLeaseExamples.resource(
      resource_id: "08919191-9191-7191-8191-919191919191",
      kind: "directory",
      path: "app/models",
      base_blob_oid: nil
    )
    blocker = ResourceLeaseExamples.lease_state(
      resource: directory,
      reference: ResourceLeaseExamples.reference(resource: directory),
      attempt_id: "A-OTHER",
      agent_id: "agent-b"
    )

    result = decide(boundary_states: [ blocker ])
    expect(result.failure).to have_attributes(code: :lease_busy)
    expect(result.failure.details).to include(resource_id: added_resource.resource_id, owner_attempt_id: "A-OTHER")
  end

  def decide(current_observations: [ current_observation ], boundary_states: [ requested.state ])
    expand.call(
      attempt_state:,
      current_observations:,
      requested_observations: [ requested ],
      boundary_states:,
      command:,
      expanded_at: "2026-08-22T10:02:00.000000Z"
    )
  end
end

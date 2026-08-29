# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::ResourceLeases::Reserve do
  subject(:reserve) { described_class.new }

  let(:first) { ResourceLeaseExamples.resource }
  let(:second) do
    ResourceLeaseExamples.resource(
      resource_id: "02919191-9191-7191-8191-919191919191",
      path: "db/schema.rb",
      base_blob_oid: nil
    )
  end
  let(:resources) { [ first, second ] }
  let(:command) do
    Coordinator::Write::Commands::ReserveWriteSet.new(
      command_id: "cmd-reserve",
      actor: ResourceLeaseExamples.actor,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id: ResourceLeaseExamples::REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: resources.map { ResourceLeaseExamples.target(_1) },
      lease_duration_seconds: 900
    )
  end

  it "Given active authority and free UUID Resources, when reserving, then emits only schema-v2 lease facts" do
    result = decide

    expect(result).to be_success
    events = result.value!.events
    expect(events.map(&:class)).to eq(
      [
        Coordinator::Write::Events::ResourceLeaseAcquiredV2,
        Coordinator::Write::Events::ResourceLeaseAcquiredV2,
        Coordinator::Write::Events::WriteSetReservedV2
      ]
    )
    expect(events.first(2).map(&:resource_id)).to eq(resources.map(&:resource_id))
    expect(events.last.resources.map(&:resource_id)).to eq(resources.map(&:resource_id))
  end

  it "Given one exact Resource is active, when reserving a set, then denies the whole set with its UUID" do
    busy = ResourceLeaseExamples.lease_state(resource: first)
    result = decide(lease_states: [ busy, Coordinator::Write::Domain::ResourceLeases::State.initial ])

    expect(result.failure).to have_attributes(code: :lease_busy)
    expect(result.failure.details).to include(resource_id: first.resource_id, owner_attempt_id: "A-LSE-A")
  end

  it "Given an active directory, when reserving its descendant, then reports the requested Resource UUID" do
    directory = ResourceLeaseExamples.resource(
      resource_id: "06919191-9191-7191-8191-919191919191",
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

    result = decide(
      resources: [ first ],
      lease_states: [ Coordinator::Write::Domain::ResourceLeases::State.initial, blocker ],
      lease_ids: [ "07919191-9191-7191-8191-919191919191" ]
    )

    expect(result.failure).to have_attributes(code: :lease_busy)
    expect(result.failure.details).to include(resource_id: first.resource_id, owner_attempt_id: "A-OTHER")
  end

  def decide(
    resources: self.resources,
    lease_states: resources.map { Coordinator::Write::Domain::ResourceLeases::State.initial },
    lease_ids: [ "04919191-9191-7191-8191-919191919191", "05919191-9191-7191-8191-919191919191" ]
  )
    reserve.call(
      attempt_state: ResourceLeaseExamples.active_attempt_state,
      lease_states:,
      command: command.new(resources: resources.map { ResourceLeaseExamples.target(_1) }),
      resources:,
      lease_set_id: ResourceLeaseExamples::LEASE_SET_ID,
      lease_ids:,
      acquired_at: ResourceLeaseExamples::ACQUIRED_AT,
      expires_at: ResourceLeaseExamples::EXPIRES_AT
    )
  end
end

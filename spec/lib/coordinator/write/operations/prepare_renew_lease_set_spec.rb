# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareRenewLeaseSet do
  subject(:prepare) { described_class.new }

  let(:leases) do
    [
      { resource_id: "02919191-9191-7191-8191-919191919191", lease_id: "04919191-9191-7191-8191-919191919191", fencing_token: 3 },
      { resource_id: "01919191-9191-7191-8191-919191919191", lease_id: "05919191-9191-7191-8191-919191919191", fencing_token: 1 }
    ]
  end
  let(:input) do
    {
      command_id: "cmd-renew-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: "03919191-9191-7191-8191-919191919191",
      leases:,
      lease_duration_seconds: 900
    }
  end

  it "builds one immutable command in Resource UUID order" do
    command = prepare.call(input).value!

    expect(command).to be_a(Coordinator::Write::Commands::RenewLeaseSet)
    expect(command.leases.map(&:resource_id)).to eq(leases.map { _1.fetch(:resource_id) }.sort_by(&:b))
    expect(command.lease_duration_seconds).to eq(900)
    expect(command).to be_frozen
  end

  it "rejects duplicate Resources, duplicate leases, malformed references, bounds, and duration" do
    duplicate_resource = prepare.call(input.merge(leases: [ leases.first, leases.first.merge(lease_id: leases.last[:lease_id]) ]))
    duplicate_lease = prepare.call(input.merge(leases: [ leases.first, leases.last.merge(lease_id: leases.first[:lease_id]) ]))
    malformed = prepare.call(input.merge(leases: [ leases.first.merge(resource_id: "abc", lease_id: "abc", fencing_token: 0) ]))
    over_bound = prepare.call(input.merge(leases: 33.times.map { lease_reference(_1) }))
    duration = prepare.call(input.merge(lease_duration_seconds: 29))

    expect([ duplicate_resource, duplicate_lease, malformed, over_bound, duration ].map { _1.failure.code }).to all(eq(:invalid_input))
  end

  def lease_reference(index)
    {
      resource_id: format("%08x-9191-7191-8191-%012x", index + 1, index + 1),
      lease_id: format("%08x-9292-7292-8292-%012x", index + 1, index + 1),
      fencing_token: 1
    }
  end
end

# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareRenewLeaseSet do
  subject(:prepare) { described_class.new }

  let(:intentions) do
    [
      { resource_id: "02919191-9191-7191-8191-919191919191", intention_id: "04919191-9191-7191-8191-919191919191", fencing_token: 3 },
      { resource_id: "01919191-9191-7191-8191-919191919191", intention_id: "05919191-9191-7191-8191-919191919191", fencing_token: 1 }
    ]
  end
  let(:input) do
    {
      command_id: "cmd-renew-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      intention_set_id: "03919191-9191-7191-8191-919191919191",
      intentions:,
      ttl_seconds: 900
    }
  end

  it "builds one immutable command in Resource UUID order" do
    command = prepare.call(input).value!

    expect(command).to be_a(Coordinator::Write::Commands::RenewLeaseSet)
    expect(command.leases.map(&:resource_id)).to eq(intentions.map { _1.fetch(:resource_id) }.sort_by(&:b))
    expect(command.lease_duration_seconds).to eq(900)
    expect(command).to be_frozen
  end

  it "rejects duplicate Resources, duplicate leases, malformed references, bounds, and duration" do
    duplicate_resource = prepare.call(input.merge(intentions: [ intentions.first, intentions.first.merge(intention_id: intentions.last[:intention_id]) ]))
    duplicate_intention = prepare.call(input.merge(intentions: [ intentions.first, intentions.last.merge(intention_id: intentions.first[:intention_id]) ]))
    malformed = prepare.call(input.merge(intentions: [ intentions.first.merge(resource_id: "abc", intention_id: "abc", fencing_token: 0) ]))
    over_bound = prepare.call(input.merge(intentions: 33.times.map { intention_reference(_1) }))
    duration = prepare.call(input.merge(ttl_seconds: 29))

    expect([ duplicate_resource, duplicate_intention, malformed, over_bound, duration ].map { _1.failure.code }).to all(eq(:invalid_input))
  end

  def intention_reference(index)
    {
      resource_id: format("%08x-9191-7191-8191-%012x", index + 1, index + 1),
      intention_id: format("%08x-9292-7292-8292-%012x", index + 1, index + 1),
      fencing_token: 1
    }
  end
end

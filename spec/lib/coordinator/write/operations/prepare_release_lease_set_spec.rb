# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareReleaseLeaseSet do
  subject(:prepare) { described_class.new }

  let(:leases) do
    [
      {
        resource_key_hash: "sha256:#{'b' * 64}",
        lease_id: "02919191-9191-7191-8191-919191919191",
        fencing_token: 3
      },
      {
        resource_key_hash: "sha256:#{'a' * 64}",
        lease_id: "01919191-9191-7191-8191-919191919191",
        fencing_token: 1
      }
    ]
  end
  let(:input) do
    {
      command_id: "cmd-release-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: "03919191-9191-7191-8191-919191919191",
      leases:
    }
  end

  it "builds one immutable command with canonical lease-reference order" do
    result = prepare.call(input)

    expect(result).to be_success
    command = result.value!
    expect(command).to be_a(Coordinator::Write::Commands::ReleaseLeaseSet)
    expect(command.leases.map(&:resource_key_hash)).to eq(
      leases.map { _1.fetch(:resource_key_hash) }.sort_by(&:b)
    )
    expect(command).to be_frozen
  end

  it "rejects duplicate resource and duplicate lease evidence before a command exists" do
    duplicate_resource = prepare.call(
      input.merge(leases: [ leases.first, leases.first.merge(lease_id: leases.last[:lease_id]) ])
    )
    duplicate_lease = prepare.call(
      input.merge(leases: [ leases.first, leases.last.merge(lease_id: leases.first[:lease_id]) ])
    )

    expect(duplicate_resource.failure.code).to eq(:invalid_input)
    expect(duplicate_lease.failure.code).to eq(:invalid_input)
  end

  it "rejects malformed hashes, lease IDs, tokens, and over-bound sets" do
    malformed = leases.first.merge(resource_key_hash: "abc", lease_id: "abc", fencing_token: 0)
    bad_reference = prepare.call(input.merge(leases: [ malformed ]))
    over_bound = prepare.call(input.merge(leases: 33.times.map do |index|
      {
        resource_key_hash: "sha256:#{format('%064x', index)}",
        lease_id: format("%08x-9191-7191-8191-%012x", index, index),
        fencing_token: 1
      }
    end))

    expect(bad_reference.failure.code).to eq(:invalid_input)
    expect(over_bound.failure.code).to eq(:invalid_input)
  end
end

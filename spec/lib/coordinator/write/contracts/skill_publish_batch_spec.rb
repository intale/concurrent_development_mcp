# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::SkillPublishBatch do
  subject(:contract) { described_class.new }

  it "accepts homogeneous ordinary skill commands with independent identities" do
    result = contract.call(input)

    expect(result).to be_success
    expect(result.to_h.fetch(:items).map { _1.fetch(:command_id) }).to eq(%w[item-1 item-2])
  end

  it "rejects empty batches, duplicate item command IDs, and invalid nested skill inputs" do
    expect(contract.call(input(items: []))).to be_failure

    duplicate = contract.call(input(items: [ item, item ]))
    invalid = contract.call(input(items: [ item.merge(name: " bad ") ]))

    expect(duplicate.errors.to_h).to have_key(:items)
    expect(invalid.errors.to_h).to have_key(:items)
  end

  it "rejects internal command identities at both public Batch boundaries" do
    outer = contract.call(input(command_id: "internal:batch:reserved"))
    nested = contract.call(input(items: [ item(command_id: "internal:item:reserved") ]))

    expect(outer.errors.to_h).to have_key(:command_id)
    expect(nested.errors.to_h).to have_key(:items)
  end

  it "rejects collections and canonical envelopes above their independent limits" do
    too_many = (Coordinator::Shared::Types::OPERATION_BATCH_MAXIMUM_ITEMS + 1).times.map do |index|
      item(command_id: "item-#{index}", name: "skill-#{index}")
    end
    oversized_assets = 3.times.map do |index|
      {
        path: "assets/payload-#{index}.bin",
        executable: false,
        content: {
          encoding: "binary",
          media_type: "application/octet-stream",
          base64: [ "a" * 800_000 ].pack("m0")
        }
      }
    end

    count_result = contract.call(input(items: too_many))
    byte_result = contract.call(input(items: [ item(assets: oversized_assets) ]))

    expect(count_result.errors.to_h).to have_key(:items)
    expect(byte_result.errors.to_h.fetch(nil)).to include(/canonical batch input exceeds/)
  end

  def input(**overrides)
    {
      command_id: "batch-command",
      actor: { kind: "agent", id: "agent-1" },
      batch_id: SecureRandom.uuid_v7,
      items: [ item, item(command_id: "item-2", name: "second") ]
    }.merge(overrides)
  end

  def item(**overrides)
    {
      command_id: "item-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: []
    }.merge(overrides)
  end
end

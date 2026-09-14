# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareExpandWriteSet do
  subject(:prepare) { described_class.new }

  let(:resources) do
    [
      { resource_id: "02919191-9191-7191-8191-919191919191" },
      { resource_id: "01919191-9191-7191-8191-919191919191", base_blob_oid: "b" * 40 }
    ]
  end
  let(:input) do
    {
      command_id: "cmd-lse-expand-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      intention_set_id: "03919191-9191-7191-8191-919191919191",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources:
    }
  end

  it "builds one immutable expansion with canonical Resource UUID targets" do
    command = prepare.call(input).value!

    expect(command).to be_a(Coordinator::Write::Commands::ExpandWriteSet)
    expect(command.resources.map(&:resource_id)).to eq(resources.map { _1.fetch(:resource_id) }.sort_by(&:b))
    expect(command).to be_frozen
  end

  it "collapses equal UUID targets and rejects conflicting base evidence" do
    duplicate = resources.first
    expect(prepare.call(input.merge(resources: [ duplicate, duplicate ])).value!.resources.length).to eq(1)
    expect(
      prepare.call(input.merge(resources: [ duplicate, duplicate.merge(base_blob_oid: "c" * 40) ])).failure.code
    ).to eq(:resource_evidence_conflict)
  end

  it "rejects malformed set IDs, Resource IDs, bounds, and Git evidence" do
    invalid_set = prepare.call(input.merge(intention_set_id: "not-a-uuid"))
    invalid_resource = prepare.call(input.merge(resources: [ { resource_id: "not-a-uuid" } ]))
    over_bound = prepare.call(input.merge(resources: 33.times.map { { resource_id: test_uuid(_1) } }))
    bad_oid = prepare.call(input.merge(base_commit_oid: "ABC"))

    expect(invalid_set.failure.code).to eq(:invalid_input)
    expect(invalid_resource.failure.code).to eq(:invalid_input)
    expect(over_bound.failure.code).to eq(:invalid_input)
    expect(bad_oid.failure.code).to eq(:invalid_git_oid)
  end

  def test_uuid(index)
    format("%08x-9191-7191-8191-%012x", index + 1, index + 1)
  end
end

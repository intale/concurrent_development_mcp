# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareExpandWriteSet do
  subject(:prepare) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-lse-expand-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: "01919191-9191-7191-8191-919191919191",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [
        { kind: "file", path: "./app/models/user.rb", base_blob_oid: "b" * 40 },
        { kind: "file", path: "app/services/capture.rb" }
      ]
    }
  end

  it "validates and constructs one immutable command with sorted normalized resources" do
    result = prepare.call(input)

    expect(result).to be_success
    command = result.value!
    expect(command).to be_a(Coordinator::Write::Commands::ExpandWriteSet)
    expect(command.lease_set_id).to eq("01919191-9191-7191-8191-919191919191")
    expect(command.resources.map(&:path)).to eq(command.resources.sort_by { _1.resource_key_hash.b }.map(&:path))
    expect(command.resources.map(&:path)).to contain_exactly(
      "app/models/user.rb",
      "app/services/capture.rb"
    )
    expect(command).to be_frozen
  end

  it "collapses aliases with equal evidence and rejects aliases with conflicting evidence" do
    aliases = [
      { kind: "file", path: "app/./models/user.rb", base_blob_oid: "b" * 40 },
      { kind: "file", path: "app/services/../models/user.rb", base_blob_oid: "b" * 40 }
    ]
    conflict = aliases.last.merge(base_blob_oid: "c" * 40)

    expect(prepare.call(input.merge(resources: aliases)).value!.resources.length).to eq(1)
    expect(prepare.call(input.merge(resources: [ aliases.first, conflict ])).failure.code).to eq(
      :resource_evidence_conflict
    )
  end

  it "rekeys normalized transport resources from the authoritative repository scope" do
    command = prepare.call(input).value!
    scoped = prepare.scope_for_repository(
      command,
      repository_registration: RepositoryScenario.registration
    ).value!

    expect(scoped.resources).to all(have_attributes(policy_version: "coordinator-resource-key/v2"))
    expect(scoped.resources.map(&:path)).to eq(
      scoped.resources.sort_by { _1.resource_key_hash.b }.map(&:path)
    )
    expect(scoped.resources.map(&:resource_key_hash)).not_to eq(command.resources.map(&:resource_key_hash))
  end

  it "rejects invalid set IDs, bounds, and Git evidence before a command exists" do
    invalid_set = prepare.call(input.merge(lease_set_id: "not-a-uuid"))
    over_bound = prepare.call(
      input.merge(resources: 33.times.map { { kind: "file", path: "file-#{_1}.rb" } })
    )
    bad_oid = prepare.call(input.merge(base_commit_oid: "ABC"))

    expect(invalid_set.failure.code).to eq(:invalid_input)
    expect(over_bound.failure.code).to eq(:invalid_input)
    expect(bad_oid.failure.code).to eq(:invalid_git_oid)
  end
end

# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::PrepareReserveWriteSet do
  subject(:prepare) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-lse-100",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [
        { kind: "file", path: "./app/models/user.rb", base_blob_oid: "b" * 40 },
        { kind: "file", path: "app/services/capture.rb" }
      ],
      lease_duration_seconds: 900
    }
  end

  it "validates and constructs one immutable command with sorted normalized resources" do
    result = prepare.call(input)

    expect(result).to be_success
    command = result.value!
    expect(command).to be_a(Coordinator::Write::Commands::ReserveWriteSet)
    expect(command.resources.map(&:path)).to eq(command.resources.sort_by { _1.resource_key_hash.b }.map(&:path))
    expect(command.resources.map(&:path)).to contain_exactly(
      "app/models/user.rb",
      "app/services/capture.rb"
    )
    expect(command).to be_frozen
  end

  it "collapses semantic aliases with equal evidence" do
    result = prepare.call(
      input.merge(
        resources: [
          { kind: "file", path: "app/./models/user.rb", base_blob_oid: "b" * 40 },
          { kind: "file", path: "app/services/../models/user.rb", base_blob_oid: "b" * 40 }
        ]
      )
    )

    expect(result.value!.resources.length).to eq(1)
  end

  it "rekeys normalized transport resources from the authoritative repository scope" do
    command = prepare.call(input).value!
    scoped = prepare.scope_for_repository(
      command,
      repository_registration: RepositoryScenario.registration
    ).value!

    expect(scoped.resources).to all(have_attributes(policy_version: "coordinator-resource-key/v2"))
    expect(scoped.resources.map(&:resource_key)).to all(start_with(
      "scope:#{RepositoryScenario::DEFAULT_SCOPE}:repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:"
    ))
  end

  it "rejects conflicting duplicate evidence and invalid bounds before a command exists" do
    conflict = prepare.call(
      input.merge(
        resources: [
          { kind: "file", path: "app/models/user.rb", base_blob_oid: "b" * 40 },
          { kind: "file", path: "app/./models/user.rb", base_blob_oid: "c" * 40 }
        ]
      )
    )
    over_bound = prepare.call(
      input.merge(resources: 33.times.map { { kind: "file", path: "file-#{_1}.rb" } })
    )
    bad_duration = prepare.call(input.merge(lease_duration_seconds: 29))
    bad_oid = prepare.call(input.merge(base_commit_oid: "ABC"))

    expect(conflict.failure.code).to eq(:resource_evidence_conflict)
    expect(over_bound.failure.code).to eq(:invalid_input)
    expect(bad_duration.failure.code).to eq(:invalid_input)
    expect(bad_oid.failure.code).to eq(:invalid_git_oid)
  end
end

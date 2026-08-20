# frozen_string_literal: true

RSpec.describe Coordinator::Operations::PrepareAcquireWorkItem do
  subject(:operation) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-300",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [
        {
          repository_id: "billing",
          commit_oid: "0123456789abcdef0123456789abcdef01234567"
        }
      ]
    }
  end

  it "builds a strict command and derives the Git object format" do
    result = operation.call(input)

    expect(result).to be_success
    expect(result.value!).to eq(
      Coordinator::Commands::AcquireWorkItem.new(
        command_id: "cmd-300",
        actor: Coordinator::Commands::Actor.new(kind: "agent", id: "agent-a"),
        change_set_id: "CS-100",
        work_item_id: "W-200",
        attempt_id: "A-300",
        base_snapshots: [
          Coordinator::RepositorySnapshotV1.new(
            repository_id: "billing",
            object_format: "sha1",
            commit_oid: "0123456789abcdef0123456789abcdef01234567"
          )
        ]
      )
    )
  end

  it "derives sha256 without performing a Git lookup" do
    result = operation.call(
      input.merge(
        base_snapshots: [
          { repository_id: "billing", commit_oid: "a" * 64 }
        ]
      )
    )

    expect(result.value!.base_snapshots.sole.object_format).to eq("sha256")
  end

  it "returns invalid_git_oid for noncanonical OIDs before command execution" do
    uppercase = operation.call(
      input.merge(
        base_snapshots: [
          { repository_id: "billing", commit_oid: "A" * 40 }
        ]
      )
    )
    empty = operation.call(
      input.merge(
        base_snapshots: [
          { repository_id: "billing", commit_oid: "" }
        ]
      )
    )

    expect(uppercase.failure.code).to eq(:invalid_git_oid)
    expect(empty.failure.code).to eq(:invalid_git_oid)
  end

  it "leaves snapshot count and repository matching to the GWT decision" do
    result = operation.call(input.merge(base_snapshots: []))

    expect(result).to be_success
    expect(result.value!.base_snapshots).to be_empty
  end

  it "rejects non-agent attribution and unknown input keys" do
    wrong_actor = operation.call(input.merge(actor: { kind: "user", id: "user-1" }))
    unknown_key = operation.call(input.merge(unexpected: true))

    expect(wrong_actor.failure.code).to eq(:invalid_input)
    expect(unknown_key.failure.code).to eq(:invalid_input)
  end
end

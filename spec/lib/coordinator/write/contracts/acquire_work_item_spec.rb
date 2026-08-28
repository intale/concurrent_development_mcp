# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::AcquireWorkItem do
  subject(:contract) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-300",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-100",
      work_item_id: "W-200",
      attempt_id: "A-300",
      base_snapshots: [
        {
          repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
          commit_oid: "0123456789abcdef0123456789abcdef01234567"
        }
      ]
    }
  end

  it "accepts the strict public acquisition shape" do
    expect(contract.call(input)).to be_success
  end

  it "rejects unknown keys, non-agent attribution, invalid identifiers, and invalid repositories" do
    result = contract.call(
      input.merge(
        command_id: "bad command",
        actor: { kind: "user", id: "bad actor" },
        base_snapshots: [ { repository_id: "Billing!", commit_oid: "anything" } ],
        unexpected: true
      )
    )

    expect(result).to be_failure
    expect(result.errors.to_h).to include(:command_id, :actor, :base_snapshots, :unexpected)
  end

  it "bounds structurally valid evidence before the domain count decision" do
    snapshots = 101.times.map do
      { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "a" * 40 }
    end

    expect(contract.call(input.merge(base_snapshots: snapshots)).errors.to_h).to include(:base_snapshots)
  end
end

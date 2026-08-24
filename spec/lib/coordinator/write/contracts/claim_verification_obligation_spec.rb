# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::ClaimVerificationObligation do
  subject(:contract) { described_class.new }

  let(:valid_input) do
    {
      command_id: "cmd-claim-1",
      actor: { kind: "agent", id: "agent-blue" },
      obligation_id: "obl-rails-4-5",
      claim_duration_seconds: 300
    }
  end

  it "accepts the exact version-1 public claim input" do
    expect(contract.call(valid_input)).to be_success
  end

  it "rejects unknown keys, non-agent attribution, invalid identities, and out-of-range durations" do
    cases = [
      valid_input.merge(extra: true),
      valid_input.merge(actor: { kind: "system", id: "claim-policy" }),
      valid_input.merge(obligation_id: "contains/slash"),
      valid_input.merge(claim_duration_seconds: 29),
      valid_input.merge(claim_duration_seconds: 3_601)
    ]

    expect(cases.map { contract.call(_1).failure? }).to all(be(true))
  end
end

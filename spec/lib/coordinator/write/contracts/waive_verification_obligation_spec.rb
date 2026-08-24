# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::WaiveVerificationObligation do
  subject(:contract) { described_class.new }

  let(:input) do
    {
      command_id: "cmd-waive-obligation",
      actor: { kind: "user", id: "user-label" },
      obligation_id: "VO-1",
      obligation_validity_input_digest: CandidateObligationExamples.digest("validity"),
      reason: { code: "accepted_risk", summary: "Accept the exact compatibility risk." }
    }
  end

  it "accepts only the strict exact user-attributed waiver document" do
    expect(contract.call(input)).to be_success
    expect(contract.call(input.merge(actor: { kind: "agent", id: "agent-a" }))).to be_failure
    expect(contract.call(input.merge(extra: true))).to be_failure
    expect(contract.call(input.merge(reason: input.fetch(:reason).merge(extra: true)))).to be_failure
  end

  it "bounds identity, digest, reason code, and reason summary" do
    expect(contract.call(input.merge(command_id: "invalid id"))).to be_failure
    expect(contract.call(input.merge(obligation_validity_input_digest: "not-a-digest"))).to be_failure
    expect(contract.call(input.merge(reason: { code: "bypass", summary: "No." }))).to be_failure
    expect(contract.call(input.merge(reason: { code: "other", summary: "x" * 2_001 }))).to be_failure
  end
end

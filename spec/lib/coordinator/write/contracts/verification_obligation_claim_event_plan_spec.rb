# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::VerificationObligationClaimEventPlan do
  subject(:contract) { described_class.new }

  let(:obligation) { CandidateObligationExamples.obligation }
  let(:reference) do
    CandidateObligationExamples.reference(
      id: "01919191-9191-7191-8191-919191919191",
      type: "VerificationObligationCreated",
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision: 0
    )
  end
  let(:state) do
    Coordinator::Write::Domain::VerificationObligationClaims::State.new(
      obligation:,
      obligation_event: reference,
      claim: nil
    )
  end
  let(:command) do
    Coordinator::Write::Commands::ClaimVerificationObligation.new(
      command_id: "cmd-claim-1",
      actor: { kind: "agent", id: "agent-blue" },
      obligation_id: obligation.obligation_id,
      claim_duration_seconds: 300
    )
  end
  let(:claim_id) { "02919191-9191-7191-8191-919191919191" }
  let(:claimed_at) { "2026-08-24T07:00:00.000000Z" }
  let(:plan) do
    Coordinator::Write::Domain::VerificationObligationClaims::Claim.new.call(
      state:,
      command:,
      claim_id:,
      claimed_at:
    ).value!
  end

  it "accepts the exact decider plan" do
    expect(contract.call(plan:, state:, command:, claim_id:, claimed_at:)).to be_success
  end

  it "rejects an otherwise-shaped claim written to another obligation stream" do
    invalid = Coordinator::Write::Domain::EventPlan.new(
      writes: [
        Coordinator::Write::Domain::EventWrite.new(
          stream: Coordinator::Write::StreamFactory.new.verification_obligation("obl-other"),
          event: plan.events.sole
        )
      ]
    )

    expect(contract.call(plan: invalid, state:, command:, claim_id:, claimed_at:)).to be_failure
  end
end

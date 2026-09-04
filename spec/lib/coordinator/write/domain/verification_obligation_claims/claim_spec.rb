# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::VerificationObligationClaims::Claim do
  subject(:decider) { described_class.new }

  let(:obligation) { CandidateObligationExamples.obligation }
  let(:obligation_event) do
    CandidateObligationExamples.reference(
      id: "01919191-9191-7191-8191-919191919191",
      type: "VerificationObligationCreated",
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision: 0
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
  let(:state) do
    Coordinator::Write::Domain::VerificationObligationClaims::State.new(
      obligation:,
      obligation_event:,
      claim: nil
    )
  end

  it "VER-CLAIM-SUCCESS-01 returns one token-1 claim for an unclaimed obligation" do
    result = decider.call(state:, command:, claim_id:, claimed_at:)

    expect(result).to be_success
    expect(result.value!.writes.sole).to have_attributes(
      stream: have_attributes(
        context: "DevelopmentIntegration",
        stream_name: "VerificationObligation",
        stream_id: obligation.obligation_id
      ),
      event: have_attributes(
        obligation_id: obligation.obligation_id,
        claim_id:,
        claimant_id: "agent-blue",
        fencing_token: 1,
        expires_at: "2026-08-24T07:05:00.000000Z"
      )
    )
  end

  it "VER-CLAIM-ACTIVE-02 returns the current claim and no event plan before expiry" do
    active = claimed_event
    active_state = state.new(claim: active)

    result = decider.call(
      state: active_state,
      command: command.new(actor: { kind: "agent", id: "agent-green" }),
      claim_id: "03919191-9191-7191-8191-919191919191",
      claimed_at: "2026-08-24T07:04:59.999999Z"
    )

    expect(result).to be_failure
    expect(result.failure.to_h).to include(
      code: :verification_obligation_already_claimed,
      details: {
        obligation_id: obligation.obligation_id,
        claim_id: active.claim_id,
        claimant_id: "agent-blue",
        fencing_token: 1,
        expires_at: "2026-08-24T07:05:00.000000Z"
      }
    )
  end

  it "VER-CLAIM-RECLAIM-03 permits reclaim at the exact expiry with the next token" do
    result = decider.call(
      state: state.new(claim: claimed_event),
      command: command.new(actor: { kind: "agent", id: "agent-green" }),
      claim_id: "03919191-9191-7191-8191-919191919191",
      claimed_at: "2026-08-24T07:05:00.000000Z"
    )

    expect(result.value!.events.sole).to have_attributes(
      claimant_id: "agent-green",
      fencing_token: 2,
      expires_at: "2026-08-24T07:10:00.000000Z"
    )
  end

  it "VER-CLAIM-NOT-FOUND-07 returns a zero-event typed denial" do
    result = decider.call(
      state: Coordinator::Write::Domain::VerificationObligationClaims::State.initial,
      command:,
      claim_id:,
      claimed_at:
    )

    expect(result.failure.to_h).to eq(
      code: :verification_obligation_not_found,
      message: "Verification obligation does not exist",
      details: { obligation_id: obligation.obligation_id }
    )
  end

  def claimed_event
    Coordinator::Write::Events::VerificationObligationClaimedV2.new(
      obligation_id: obligation.obligation_id,
      claim_id:,
      claimant_id: "agent-blue",
      fencing_token: 1,
      expires_at: "2026-08-24T07:05:00.000000Z"
    )
  end
end

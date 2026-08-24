# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::VerificationObligationWaivers::Waive do
  subject(:decider) { described_class.new }

  let(:obligation) { CandidateObligationExamples.obligation }
  let(:obligation_event) { VerificationEvidenceExamples.obligation_event }
  let(:command) do
    Coordinator::Write::Commands::WaiveVerificationObligation.new(
      command_id: "cmd-waive",
      actor: { kind: "user", id: "user-label" },
      obligation_id: obligation.obligation_id,
      obligation_validity_input_digest: obligation.validity_input_digest,
      reason: { code: "accepted_risk", summary: "Accept exact risk." }
    )
  end
  let(:state) do
    Coordinator::Write::Domain::VerificationObligationWaivers::State.new(
      **described_state,
      obligation:,
      obligation_event:,
      policy_current: true
    )
  end
  let(:described_state) do
    {
      satisfied: nil,
      satisfied_event: nil,
      failed: nil,
      failed_event: nil,
      waived: nil,
      waived_event: nil,
      invalidated: nil,
      invalidated_event: nil
    }
  end

  it "decides one exact waiver from open state" do
    result = decide

    expect(result).to be_success
    expect(result.value!.writes.sole).to have_attributes(
      stream: Coordinator::Write::StreamFactory.new.verification_obligation(obligation.obligation_id),
      event: have_attributes(
        obligation_id: obligation.obligation_id,
        obligation_event:,
        previous_status: "open",
        previous_terminal_event: nil,
        reason: command.reason,
        waiver_input_digest: CandidateObligationExamples.digest("waiver-input")
      )
    )
  end

  it "allows an exact current failed obligation to be waived" do
    failed = VerificationEvidenceExamples.failed
    failed_event = VerificationEvidenceExamples.outcome_reference(type: "VerificationObligationFailed")
    failed_state = state.new(failed:, failed_event:)

    event = decide(state: failed_state).value!.events.sole

    expect(event).to have_attributes(previous_status: "failed", previous_terminal_event: failed_event)
  end

  it "denies non-user, stale binding/policy, satisfied, and already-waived states" do
    expect(decide(command: command.new(actor: { kind: "agent", id: "agent-a" })).failure.code)
      .to eq(:verification_obligation_waiver_requires_user)
    expect(decide(state: state.new(policy_current: false)).failure.code)
      .to eq(:verification_obligation_policy_stale)
    expect(
      decide(command: command.new(obligation_validity_input_digest: CandidateObligationExamples.digest("old"))).failure.code
    ).to eq(:verification_obligation_binding_stale)

    satisfied = VerificationEvidenceExamples.satisfied
    satisfied_state = state.new(
      satisfied:,
      satisfied_event: VerificationEvidenceExamples.outcome_reference(
        type: "VerificationObligationSatisfied"
      )
    )
    expect(decide(state: satisfied_state).failure.code).to eq(:verification_obligation_terminal)

    waiver = decide.value!.events.sole
    waived_state = state.new(
      waived: waiver,
      waived_event: VerificationEvidenceExamples.outcome_reference(
        type: "VerificationObligationWaived"
      )
    )
    expect(decide(state: waived_state).failure.code).to eq(:verification_obligation_already_waived)
  end

  def decide(state: self.state, command: self.command)
    decider.call(
      state:,
      command:,
      waiver_input_digest: CandidateObligationExamples.digest("waiver-input"),
      waived_at: VerificationEvidenceExamples::SUBMITTED_AT
    )
  end
end

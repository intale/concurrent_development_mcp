# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::VerificationObligationInvalidations::Invalidate do
  subject(:decider) { described_class.new }

  let(:obligation) { CandidateObligationExamples.obligation }
  let(:obligation_event) { VerificationEvidenceExamples.obligation_event }
  let(:superseding_reference) do
    CandidateObligationExamples.partition_reference.new(stream_revision: 1)
  end
  let(:superseding_partition) do
    payload = Coordinator::Write::Events::DecisionPartitionAdvancedV1.new(
      partition: CandidateObligationExamples.partition,
      partition_revision: 1,
      decision: CandidateObligationExamples.decision_head,
      active_decisions: [ CandidateObligationExamples.decision_head ],
      change_kind: "corrected",
      advanced_at: CandidateObligationExamples::TIMESTAMP
    )
    Coordinator::Write::CandidateObligations::PersistedEventV1.new(
      event: PgEventstore::Event.new,
      payload:,
      reference: superseding_reference
    )
  end
  let(:command) do
    Coordinator::Write::Commands::InvalidateVerificationObligation.new(
      command_id: "verification-obligation-invalidation-v1:digest",
      actor: { kind: "system", id: "verification-obligation-validity-policy" },
      obligation_id: obligation.obligation_id,
      obligation_event:,
      superseding_partition_event: superseding_reference,
      rule_version: "verification-obligation-validity/v1"
    )
  end
  let(:state) do
    Coordinator::Write::Domain::VerificationObligationInvalidations::State.new(
      obligation:,
      obligation_event:,
      satisfied: nil,
      satisfied_event: nil,
      failed: nil,
      failed_event: nil,
      waived: nil,
      waived_event: nil,
      invalidated: nil,
      invalidated_event: nil
    )
  end

  it "invalidates the exact obligation after its policy partition advances" do
    result = decide

    expect(result).to be_success
    expect(result.value!.writes.sole).to have_attributes(
      stream: Coordinator::Write::StreamFactory.new.verification_obligation(obligation.obligation_id),
      event: have_attributes(
        obligation_id: obligation.obligation_id,
        obligation_event:,
        invalidated_policy: obligation.policy,
        superseding_partition_event: superseding_reference,
        previous_status: "open",
        previous_terminal_event: nil,
        reason: "policy_partition_advanced",
        rule_version: "verification-obligation-validity/v1"
      )
    )
  end

  it "denies an unchanged partition and an already invalidated obligation" do
    current_partition = superseding_partition.new(
      reference: obligation.policy.partition_event,
      payload: superseding_partition.payload.new(partition_revision: 0)
    )
    expect(decide(superseding_partition: current_partition).failure.code)
      .to eq(:verification_obligation_policy_still_current)

    invalidated = decide.value!.events.sole
    invalidated_state = state.new(
      invalidated:,
      invalidated_event: VerificationEvidenceExamples.outcome_reference(
        type: "VerificationObligationInvalidated"
      )
    )
    expect(decide(state: invalidated_state).failure.code)
      .to eq(:verification_obligation_already_invalidated)
  end

  def decide(state: self.state, superseding_partition: self.superseding_partition)
    decider.call(
      state:,
      command:,
      superseding_partition:,
      invalidated_at: VerificationEvidenceExamples::SUBMITTED_AT
    )
  end
end

# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::VerificationEvidenceEventPlan do
  subject(:contract) { described_class.new }

  let(:state) { VerificationEvidenceExamples.state }
  let(:command) { VerificationEvidenceExamples.command }
  let(:evidence_id) { "05919191-9191-7191-8191-919191919191" }
  let(:assessment_input_digest) { VerificationEvidenceExamples.digest("new-assessment") }
  let(:submitted_at) { VerificationEvidenceExamples::SUBMITTED_AT }
  let(:plan) do
    Coordinator::Write::Domain::VerificationEvidence::Submit.new.call(
      state:,
      command:,
      evidence_id:,
      assessment_input_digest:,
      submitted_at:
    ).value!
  end

  it "accepts the exact deterministic evidence decision" do
    expect(contract.call(plan:, state:, command:, evidence_id:, assessment_input_digest:, submitted_at:)).to be_success
  end

  it "rejects a shaped plan whose evidence fact was altered" do
    altered_event = plan.events.sole.new(evidence_kind: "contract_compatibility_review")
    altered = plan.new(writes: [ plan.writes.sole.new(event: altered_event) ])

    expect(
      contract.call(
        plan: altered,
        state:,
        command:,
        evidence_id:,
        assessment_input_digest:,
        submitted_at:
      )
    ).to be_failure
  end
end

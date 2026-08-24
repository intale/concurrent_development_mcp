# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::VerificationEvidenceEventPlan do
  subject(:contract) { described_class.new }

  let(:state) { VerificationEvidenceExamples.state }
  let(:command) { VerificationEvidenceExamples.command }
  let(:evidence_id) { "05919191-9191-7191-8191-919191919191" }
  let(:assessment_input_digest) { VerificationEvidenceExamples.digest("new-assessment") }
  let(:evidence_event) { VerificationEvidenceExamples.evidence_reference(revision: 2, evidence_id:) }
  let(:submitted_at) { VerificationEvidenceExamples::SUBMITTED_AT }
  let(:plan) do
    Coordinator::Write::Domain::VerificationEvidence::Submit.new.call(
      state:,
      command:,
      evidence_id:,
      assessment_input_digest:,
      evidence_event:,
      submitted_at:
    ).value!
  end

  it "accepts the exact deterministic evidence decision" do
    expect(contract.call(plan:, state:, command:, evidence_id:, assessment_input_digest:, evidence_event:, submitted_at:)).to be_success
  end

  it "rejects a future evidence reference with a skipped stream revision" do
    invalid_reference = evidence_event.new(stream_revision: 3)

    expect(
      contract.call(
        plan:,
        state:,
        command:,
        evidence_id:,
        assessment_input_digest:,
        evidence_event: invalid_reference,
        submitted_at:
      )
    ).to be_failure
  end

  it "rejects a shaped plan whose terminal decision was altered" do
    existing = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    complete_state = VerificationEvidenceExamples.state(evidence: [ existing ])
    final_command = VerificationEvidenceExamples.command(evidence_kind: "contract_compatibility_review")
    final_reference = VerificationEvidenceExamples.evidence_reference(revision: 3, evidence_id:)
    exact = Coordinator::Write::Domain::VerificationEvidence::Submit.new.call(
      state: complete_state,
      command: final_command,
      evidence_id:,
      assessment_input_digest:,
      evidence_event: final_reference,
      submitted_at:
    ).value!
    altered_outcome = exact.events.last.new(outcome_digest: VerificationEvidenceExamples.digest("altered"))
    altered = exact.new(writes: [ exact.writes.first, exact.writes.last.new(event: altered_outcome) ])

    expect(
      contract.call(
        plan: altered,
        state: complete_state,
        command: final_command,
        evidence_id:,
        assessment_input_digest:,
        evidence_event: final_reference,
        submitted_at:
      )
    ).to be_failure
  end
end

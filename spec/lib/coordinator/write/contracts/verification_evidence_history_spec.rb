# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::VerificationEvidenceHistory do
  subject(:contract) { described_class.new }

  let(:obligation_id) { VerificationEvidenceExamples.obligation.obligation_id }

  it "accepts absent, open partial, satisfied, and failed histories" do
    expect(contract.call(state: Coordinator::Write::Domain::VerificationEvidence::State.initial, obligation_id:)).to be_success

    partial = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    open_state = VerificationEvidenceExamples.state(evidence: [ partial ])
    expect(contract.call(state: open_state, obligation_id:)).to be_success

    final_observation = VerificationEvidenceExamples.observation(
      evidence_kind: "contract_compatibility_review",
      revision: 6,
      evidence_id: "06919191-9191-7191-8191-919191919191"
    )
    satisfied_state = VerificationEvidenceExamples.state(
      evidence: [ partial, final_observation ],
      satisfied: VerificationEvidenceExamples.satisfied
    )
    expect(contract.call(state: satisfied_state, obligation_id:)).to be_success

    failed_observation = VerificationEvidenceExamples.observation(
      evidence_kind: "combined_tests",
      conclusion: "failed",
      revision: 5
    )
    failed_state = VerificationEvidenceExamples.state(
      evidence: [ failed_observation ],
      failed: VerificationEvidenceExamples.failed
    )
    expect(contract.call(state: failed_state, obligation_id:)).to be_success
  end

  it "rejects duplicate assessments, mismatched references, and two terminal outcomes" do
    observation = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    duplicate = observation.new(event: observation.event.new(event_id: "07919191-9191-7191-8191-919191919191", stream_revision: 3))
    duplicated_state = VerificationEvidenceExamples.state(evidence: [ observation, duplicate ])
    expect(contract.call(state: duplicated_state, obligation_id:)).to be_failure

    mismatched_reference = observation.new(
      event: observation.event.new(stream_id: "08919191-9191-7191-8191-919191919191")
    )
    expect(
      contract.call(
        state: VerificationEvidenceExamples.state(evidence: [ mismatched_reference ]),
        obligation_id:
      )
    ).to be_failure

    failed_observation = VerificationEvidenceExamples.observation(
      evidence_kind: "combined_tests",
      conclusion: "failed",
      revision: 5
    )
    impossible = VerificationEvidenceExamples.state(
      evidence: [ failed_observation ],
      satisfied: VerificationEvidenceExamples.satisfied,
      failed: VerificationEvidenceExamples.failed
    )
    expect(contract.call(state: impossible, obligation_id:)).to be_failure
  end

end

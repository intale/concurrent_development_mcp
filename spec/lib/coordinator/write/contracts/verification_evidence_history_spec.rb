# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::VerificationEvidenceHistory do
  subject(:contract) { described_class.new }

  let(:obligation_id) { VerificationEvidenceExamples.obligation.obligation_id }

  it "accepts absent, open partial, satisfied, and failed histories" do
    expect(contract.call(state: Coordinator::Write::Domain::VerificationEvidence::State.initial, obligation_id:)).to be_success

    partial = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    open_state = VerificationEvidenceExamples.state(evidence: [ partial ])
    expect(contract.call(state: open_state, obligation_id:)).to be_success

    satisfaction_plan = decide(
      state: open_state,
      command: VerificationEvidenceExamples.command(evidence_kind: "contract_compatibility_review"),
      revision: 3
    )
    final_observation = observation_from(satisfaction_plan.events.first, revision: 3)
    satisfied_state = VerificationEvidenceExamples.state(
      evidence: [ partial, final_observation ],
      satisfied: satisfaction_plan.events.last
    )
    expect(contract.call(state: satisfied_state, obligation_id:)).to be_success

    failure_plan = decide(command: VerificationEvidenceExamples.command(conclusion: "failed"))
    failed_observation = observation_from(failure_plan.events.first, revision: 2)
    failed_state = VerificationEvidenceExamples.state(
      evidence: [ failed_observation ],
      failed: failure_plan.events.last
    )
    expect(contract.call(state: failed_state, obligation_id:)).to be_success
  end

  it "rejects duplicate assessments, mismatched references, and two terminal outcomes" do
    observation = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    duplicate = observation.new(event: observation.event.new(event_id: "07919191-9191-7191-8191-919191919191", stream_revision: 3))
    duplicated_state = VerificationEvidenceExamples.state(evidence: [ observation, duplicate ])
    expect(contract.call(state: duplicated_state, obligation_id:)).to be_failure

    mismatched_reference = observation.new(
      event: observation.event.new(event_id: "08919191-9191-7191-8191-919191919191")
    )
    expect(
      contract.call(
        state: VerificationEvidenceExamples.state(evidence: [ mismatched_reference ]),
        obligation_id:
      )
    ).to be_failure

    failure_plan = decide(command: VerificationEvidenceExamples.command(conclusion: "failed"))
    failed_observation = observation_from(failure_plan.events.first, revision: 2)
    impossible = VerificationEvidenceExamples.state(
      evidence: [ failed_observation ],
      satisfied: satisfaction_from(failed_observation),
      failed: failure_plan.events.last
    )
    expect(contract.call(state: impossible, obligation_id:)).to be_failure
  end

  def decide(
    state: VerificationEvidenceExamples.state,
    command: VerificationEvidenceExamples.command,
    revision: 2
  )
    evidence_id = "05919191-9191-7191-8191-919191919191"
    Coordinator::Write::Domain::VerificationEvidence::Submit.new.call(
      state:,
      command:,
      evidence_id:,
      assessment_input_digest: VerificationEvidenceExamples.digest("history-assessment", revision),
      evidence_event: VerificationEvidenceExamples.evidence_reference(revision:, evidence_id:),
      submitted_at: VerificationEvidenceExamples::SUBMITTED_AT
    ).value!
  end

  def observation_from(event, revision:)
    Coordinator::Write::CompatibilityAssessments::EvidenceObservationV1.new(
      evidence: event,
      event: VerificationEvidenceExamples.evidence_reference(revision:, evidence_id: event.evidence_id)
    )
  end

  def satisfaction_from(observation)
    obligation = VerificationEvidenceExamples.obligation
    reference = observation.decision_reference
    Coordinator::Write::Events::VerificationObligationSatisfiedV1.new(
      obligation_id: obligation.obligation_id,
      obligation_event: VerificationEvidenceExamples.obligation_event,
      policy: obligation.policy,
      selected_evidence: [ reference ],
      outcome_digest: VerificationEvidenceExamples.digest("impossible"),
      satisfied_at: VerificationEvidenceExamples::SUBMITTED_AT
    )
  end
end

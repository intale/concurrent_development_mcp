# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::VerificationEvidence::Submit do
  subject(:decider) { described_class.new }

  let(:evidence_id) { "05919191-9191-7191-8191-919191919191" }
  let(:submitted_at) { VerificationEvidenceExamples::SUBMITTED_AT }
  let(:assessment_input_digest) { VerificationEvidenceExamples.digest("new-assessment") }

  it "VER-EVIDENCE-PARTIAL-01 emits attributed evidence and absolute progress, and remains open" do
    result = decide

    expect(result).to be_success
    expect(result.value!.events.first).to match(
      have_attributes(
        evidence_id:,
        evidence_kind: "combined_tests",
        assessment: have_attributes(conclusion: "passed"),
        claim: have_attributes(claimant_id: "agent-blue", fencing_token: 1)
      )
    )
    expect(result.value!.events.drop(1)).to contain_exactly(
      have_attributes(obligation_id: VerificationEvidenceExamples.command.obligation_id, evidence_number: 1),
      have_attributes(passed_evidence_kinds: [ "combined_tests" ], missing_evidence_kinds: [ "contract_compatibility_review" ])
    )
  end

  it "VER-EVIDENCE-SATISFIED-02 leaves the terminal outcome to the evidence-outcome process" do
    existing = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    command = VerificationEvidenceExamples.command(evidence_kind: "contract_compatibility_review")

    plan = decide(state: VerificationEvidenceExamples.state(evidence: [ existing ]), command:).value!

    expect(plan.events.first).to be_a(Coordinator::Write::Events::VerificationEvidenceSubmittedV2)
    expect(plan.events.first.evidence_kind).to eq("contract_compatibility_review")
    expect(plan.events.last).to have_attributes(
      passed_evidence_kinds: %w[combined_tests contract_compatibility_review], missing_evidence_kinds: []
    )
  end

  it "VER-EVIDENCE-FAILED-03 records failed evidence without embedding an outcome" do
    command = VerificationEvidenceExamples.command(conclusion: "failed")

    plan = decide(command:).value!

    expect(plan.events.first).to have_attributes(
      evidence_id:,
      assessment: have_attributes(conclusion: "failed")
    )
    expect(plan.events.last).to have_attributes(evidence_number: 1)
    expect(plan.events.length).to eq(2)
  end

  it "VER-EVIDENCE-NONTERMINAL-04 records inconclusive and not-applicable conclusions without a terminal fact" do
    %w[inconclusive not_applicable].each do |conclusion|
      command = VerificationEvidenceExamples.command(conclusion:)

      expect(decide(command:).value!.events.map(&:class)).to eq([
        Coordinator::Write::Events::VerificationEvidenceSubmittedV2,
        Coordinator::Write::Events::ProjectionNumbers::VerificationObligationEvidenceNumberChangedV1
      ])
    end
  end

  it "records a new number without a false coverage change when an already passed kind is submitted again" do
    existing = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    plan = decide(state: VerificationEvidenceExamples.state(evidence: [ existing ])).value!

    expect(plan.events.map(&:class)).to eq([
      Coordinator::Write::Events::VerificationEvidenceSubmittedV2,
      Coordinator::Write::Events::ProjectionNumbers::VerificationObligationEvidenceNumberChangedV1
    ])
    expect(plan.events.last).to have_attributes(evidence_number: 2)
  end

  it "VER-EVIDENCE-EXPIRED-05 denies a claim at its exact expiry" do
    result = decide(submitted_at: VerificationEvidenceExamples::EXPIRES_AT)

    expect(result.failure.to_h).to include(code: :verification_obligation_claim_expired)
  end

  it "VER-EVIDENCE-FENCE-06 denies a stale claim id or fencing token" do
    stale_id = VerificationEvidenceExamples.command(claim_id: "06919191-9191-7191-8191-919191919191")
    stale_token = VerificationEvidenceExamples.command(fencing_token: 2)

    expect(decide(command: stale_id).failure.code).to eq(:verification_obligation_claim_stale)
    expect(decide(command: stale_token).failure.code).to eq(:verification_obligation_claim_stale)
  end

  it "VER-EVIDENCE-OWNER-07 denies an actor that does not own the exact claim" do
    result = decide(command: VerificationEvidenceExamples.command(actor_id: "agent-green"))

    expect(result.failure.code).to eq(:verification_obligation_claim_not_owned)
  end

  it "VER-EVIDENCE-POLICY-08 denies evidence when the authoritative policy is stale" do
    result = decide(state: VerificationEvidenceExamples.state(policy_current: false))

    expect(result.failure.code).to eq(:verification_obligation_policy_stale)
  end

  it "VER-EVIDENCE-DUPLICATE-09 denies a reused canonical assessment digest" do
    existing = VerificationEvidenceExamples.observation(
      evidence_kind: "combined_tests",
      assessment_input_digest:
    )

    result = decide(state: VerificationEvidenceExamples.state(evidence: [ existing ]))

    expect(result.failure.to_h).to include(
      code: :verification_evidence_already_submitted,
      details: include(assessment_input_digest:)
    )
  end

  it "VER-EVIDENCE-TERMINAL-10 denies evidence after a terminal fact" do
    failed = VerificationEvidenceExamples.failed

    result = decide(state: VerificationEvidenceExamples.state(failed:))

    expect(result.failure.to_h).to include(
      code: :verification_obligation_terminal,
      details: include(status: "failed")
    )
  end

  it "VER-EVIDENCE-BINDING-11 denies stale candidate or obligation input bindings" do
    command = VerificationEvidenceExamples.command
    stale = command.new(
      binding: command.binding.new(
        source_candidate: command.binding.source_candidate.new(head_commit_oid: "f" * 40)
      )
    )

    expect(decide(command: stale).failure.code).to eq(:verification_obligation_binding_stale)
  end

  it "VER-EVIDENCE-LIMIT-12 denies the thirty-third accepted evidence fact" do
    observations = Array.new(32) do |index|
      VerificationEvidenceExamples.observation(
        evidence_kind: "combined_tests",
        revision: index + 2,
        evidence_id: format("%08x-9191-7191-8191-%012x", index + 100, index + 100),
        assessment_input_digest: VerificationEvidenceExamples.digest("accepted", index)
      )
    end

    result = decide(state: VerificationEvidenceExamples.state(evidence: observations))

    expect(result.failure.to_h).to include(
      code: :verification_evidence_limit_reached,
      details: include(maximum_count: 32)
    )
  end

  def decide(
    state: VerificationEvidenceExamples.state,
    command: VerificationEvidenceExamples.command,
    submitted_at: self.submitted_at
  )
    decider.call(
      state:,
      command:,
      evidence_id:,
      assessment_input_digest:,
      submitted_at:
    )
  end
end

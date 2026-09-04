# frozen_string_literal: true

module VerificationEvidenceExamples
  module_function

  SUBMITTED_AT = "2026-08-24T08:00:00.000000Z"
  CLAIMED_AT = "2026-08-24T07:55:00.000000Z"
  EXPIRES_AT = "2026-08-24T08:05:00.000000Z"
  CLAIM_ID = "01919191-9191-7191-8191-919191919191"

  def obligation
    @obligation ||= CandidateObligationExamples.obligation
  end

  def obligation_event
    CandidateObligationExamples.reference(
      id: "02919191-9191-7191-8191-919191919191",
      type: "VerificationObligationCreated",
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision: 0
    )
  end

  def claim
    Coordinator::Write::Events::VerificationObligationClaimedV2.new(
      obligation_id: obligation.obligation_id,
      claim_id: CLAIM_ID,
      claimant_id: "agent-blue",
      fencing_token: 1,
      expires_at: EXPIRES_AT
    )
  end

  def claim_event
    CandidateObligationExamples.reference(
      id: "03919191-9191-7191-8191-919191919191",
      type: "VerificationObligationClaimed",
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision: 4
    )
  end

  def command(
    evidence_kind: "combined_tests",
    conclusion: "passed",
    findings: nil,
    actor_id: "agent-blue",
    claim_id: CLAIM_ID,
    fencing_token: 1,
    assessment_input_digest: digest("assessment", evidence_kind, conclusion)
  )
    Coordinator::Write::Commands::SubmitCompatibilityAssessment.new(
      command_id: "cmd-assess-#{evidence_kind}-#{conclusion}",
      actor: { kind: "agent", id: actor_id },
      obligation_id: obligation.obligation_id,
      claim: { claim_id:, fencing_token: },
      binding: binding,
      assessment: assessment(
        evidence_kind:,
        conclusion:,
        findings: findings || default_findings(conclusion),
        result_digest: assessment_input_digest
      )
    )
  end

  def binding
    {
      obligation_validity_input_digest: obligation.validity_input_digest,
      source_candidate: {
        candidate_id: obligation.source_candidate.candidate_id,
        head_commit_oid: obligation.source_candidate.head_commit_oid
      },
      target_candidate: {
        candidate_id: obligation.target_candidate.candidate_id,
        head_commit_oid: obligation.target_candidate.head_commit_oid
      }
    }
  end

  def assessment(
    evidence_kind:,
    conclusion:,
    findings: default_findings(conclusion),
    result_digest: digest("result", evidence_kind, conclusion)
  )
    {
      evidence_kind:,
      producer: { name: "coordinator-spec", version: "1.0.0" },
      run_id: "run-#{evidence_kind}-#{conclusion}",
      test_suite_digest: digest("suite", evidence_kind),
      environment_digest: digest("environment", evidence_kind),
      dependency_graph_digest: digest("dependencies", evidence_kind),
      result_digest:,
      conclusion:,
      findings:,
      produced_at: "2026-08-24T07:59:00.000000Z"
    }
  end

  def default_findings(conclusion)
    return [] if conclusion == "passed"

    [
      {
        code: "assessment-#{conclusion}",
        severity: "error",
        summary: "Assessment concluded #{conclusion}",
        path: nil
      }
    ]
  end

  def state(evidence: [], satisfied: nil, failed: nil, policy_current: true, latest_claim: claim)
    Coordinator::Write::Domain::VerificationEvidence::State.new(
      obligation:,
      obligation_event:,
      latest_claim:,
      latest_claim_event: latest_claim ? claim_event : nil,
      evidence:,
      satisfied:,
      failed:,
      policy_current:
    )
  end

  def evidence_reference(revision:, evidence_id:)
    CandidateObligationExamples.reference(
      id: evidence_id,
      type: "VerificationEvidenceSubmitted",
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision:
    )
  end

  def observation(
    evidence_kind:,
    conclusion: "passed",
    revision: 5,
    evidence_id: "04919191-9191-7191-8191-919191919191",
    assessment_input_digest: digest("accepted", evidence_kind, revision)
  )
    event = Coordinator::Write::Events::VerificationEvidenceSubmittedV2.new(
      evidence_id:,
      obligation_id: obligation.obligation_id,
      evidence_kind:,
      claim: {
        claim_id: claim.claim_id,
        claimant_id: claim.claimant_id,
        fencing_token: claim.fencing_token,
        claim_event:
      },
      assessment: assessment(evidence_kind:, conclusion:)
    )
    Coordinator::Write::CompatibilityAssessments::EvidenceObservationV2.new(
      evidence: event,
      event: evidence_reference(revision:, evidence_id:),
      assessment_input_digest:,
      obligation_validity_input_digest: obligation.validity_input_digest,
      policy: obligation.policy
    )
  end

  def failed
    evidence_id = "05919191-9191-7191-8191-919191919191"
    observed = observation(evidence_kind: "combined_tests", conclusion: "failed", evidence_id:)
    outcome_state = outcome_state(evidence: [ observed ])
    command = Coordinator::Write::Commands::FailVerificationObligation.new(
      command_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      actor: { kind: "system", id: "verification-evidence-outcome" },
      obligation_id: obligation.obligation_id,
      triggering_evidence_id: evidence_id,
      reason: "submitted_evidence_failed"
    )
    Coordinator::Write::Domain::VerificationObligationOutcomes::Fail.new.call(
      state: outcome_state,
      command:
    ).value!.events.last
  end

  def satisfied
    existing = observation(evidence_kind: "combined_tests", revision: 5)
    evidence_id = "06919191-9191-7191-8191-919191919191"
    final = observation(
      evidence_kind: "contract_compatibility_review",
      revision: 6,
      evidence_id:,
      assessment_input_digest: digest("satisfied-assessment")
    )
    command = Coordinator::Write::Commands::SatisfyVerificationObligation.new(
      command_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      actor: { kind: "system", id: "verification-evidence-outcome" },
      obligation_id: obligation.obligation_id,
      triggering_evidence_id: evidence_id,
      selected_evidence_ids: [ existing.evidence.evidence_id, evidence_id ]
    )
    Coordinator::Write::Domain::VerificationObligationOutcomes::Satisfy.new.call(
      state: outcome_state(evidence: [ existing, final ]),
      command:
    ).value!.events.last
  end

  def outcome_state(evidence:, terminal_status: nil, terminal_event: nil)
    Coordinator::Write::VerificationObligations::OutcomeStateV2.new(
      definition: obligation,
      definition_event: obligation_event,
      evidence:,
      selected_evidence_ids: [],
      terminal_status:,
      terminal_event:,
      latest_revision: evidence.map { _1.event.stream_revision }.max || 3
    )
  end

  def outcome_reference(type:, revision: 4)
    CandidateObligationExamples.reference(
      id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type:,
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision:
    )
  end

  def digest(*parts)
    Coordinator::Shared::CanonicalJson.new.sha256(parts)
  end

  def raw_input(**overrides)
    command = self.command(**overrides)
    command.to_h
  end
end

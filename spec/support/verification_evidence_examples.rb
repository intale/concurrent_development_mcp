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
    Coordinator::Write::Events::VerificationObligationClaimedV1.new(
      obligation_id: obligation.obligation_id,
      obligation_event:,
      claim_id: CLAIM_ID,
      claimant_id: "agent-blue",
      fencing_token: 1,
      claimed_at: CLAIMED_AT,
      expires_at: EXPIRES_AT
    )
  end

  def claim_event
    CandidateObligationExamples.reference(
      id: "03919191-9191-7191-8191-919191919191",
      type: "VerificationObligationClaimed",
      stream_name: "VerificationObligation",
      stream_id: obligation.obligation_id,
      revision: 1
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
    revision: 2,
    evidence_id: "04919191-9191-7191-8191-919191919191",
    assessment_input_digest: digest("accepted", evidence_kind, revision)
  )
    event = Coordinator::Write::Events::VerificationEvidenceSubmittedV1.new(
      obligation_id: obligation.obligation_id,
      obligation_event:,
      evidence_id:,
      evidence_kind:,
      claim: {
        claim_id: claim.claim_id,
        claimant_id: claim.claimant_id,
        fencing_token: claim.fencing_token,
        claim_event:
      },
      source_candidate: obligation.source_candidate,
      target_candidate: obligation.target_candidate,
      policy: obligation.policy,
      obligation_validity_input_digest: obligation.validity_input_digest,
      assessment: assessment(evidence_kind:, conclusion:),
      assessment_input_digest:,
      submitted_at: SUBMITTED_AT
    )
    Coordinator::Write::CompatibilityAssessments::EvidenceObservationV1.new(
      evidence: event,
      event: evidence_reference(revision:, evidence_id:)
    )
  end

  def failed
    failed_command = command(conclusion: "failed")
    Coordinator::Write::Domain::VerificationEvidence::Submit.new.call(
      state: state,
      command: failed_command,
      evidence_id: "05919191-9191-7191-8191-919191919191",
      assessment_input_digest: digest("failed-assessment"),
      evidence_event: evidence_reference(
        revision: 2,
        evidence_id: "05919191-9191-7191-8191-919191919191"
      ),
      submitted_at: SUBMITTED_AT
    ).value!.events.last
  end

  def satisfied
    existing = observation(evidence_kind: "combined_tests")
    final_command = command(evidence_kind: "contract_compatibility_review")
    Coordinator::Write::Domain::VerificationEvidence::Submit.new.call(
      state: state(evidence: [ existing ]),
      command: final_command,
      evidence_id: "06919191-9191-7191-8191-919191919191",
      assessment_input_digest: digest("satisfied-assessment"),
      evidence_event: evidence_reference(
        revision: 3,
        evidence_id: "06919191-9191-7191-8191-919191919191"
      ),
      submitted_at: SUBMITTED_AT
    ).value!.events.last
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

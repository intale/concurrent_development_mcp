# frozen_string_literal: true

module VerificationEvidenceOutcomeAcceptanceWorld
  def prepare_claimed_verification_obligation(
    prefix:,
    agent_id:,
    project_claim: false,
    claim_duration: 300
  )
    prepare_open_verification_obligation(prefix:)
    project_candidate_obligation(redeliver: true) if project_claim
    attempt = submit_verification_obligation_claim(
      agent_id:,
      command_id: "cmd-cuc-evidence-claim-#{prefix.downcase}",
      duration: claim_duration
    )
    execute_verification_obligation_claim(attempt)
    assert_acceptance_equal(false, attempt.dig(:result, "isError"), "Evidence setup claim")

    @evidence_actor_id = agent_id
    @evidence_claim_attempt = attempt
    @evidence_claim = attempt.dig(:content, "data")
    project_verification_obligation_claims(redeliver: true) if project_claim
  end

  def submit_evidence_attempt(
    command_id:,
    evidence_kind:,
    conclusion:,
    actor_id: @evidence_actor_id,
    claim: @evidence_claim,
    assessment: nil
  )
    arguments = compatibility_assessment_arguments(
      command_id:,
      evidence_kind:,
      conclusion:,
      actor_id:,
      claim:,
      assessment:
    )
    response = call_tool("compatibility_assessment_submit", arguments)
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "compatibility_assessment_submit did not return a Task handle")
    {
      command_id:,
      arguments:,
      task_id:,
      submitted_response: response
    }
  end

  def execute_evidence_attempt(attempt)
    execute_task(attempt.fetch(:task_id))
    capture_evidence_attempt(attempt)
    attempt
  end

  def capture_evidence_attempt(attempt)
    attempt[:state] = task_request("tasks/get", attempt.fetch(:task_id))
    attempt[:result] = attempt.dig(:state, "result", "result")
    attempt[:content] = attempt.dig(:result, "structuredContent")
    attempt
  end

  def compatibility_assessment_arguments(
    command_id:,
    evidence_kind:,
    conclusion:,
    actor_id:,
    claim:,
    assessment:
  )
    obligation = candidate_obligation_payload
    assessment ||= compatibility_assessment_document(
      evidence_kind:,
      conclusion:,
      produced_at: Time.now.utc.iso8601(6)
    )
    {
      command_id:,
      actor: { kind: "agent", id: actor_id },
      obligation_id: @obligation_id,
      claim: {
        claim_id: claim.fetch("claim_id"),
        fencing_token: claim.fetch("fencing_token")
      },
      binding: {
        obligation_validity_input_digest: obligation.validity_input_digest,
        source_candidate: {
          candidate_id: obligation.source_candidate.candidate_id,
          head_commit_oid: obligation.source_candidate.head_commit_oid
        },
        target_candidate: {
          candidate_id: obligation.target_candidate.candidate_id,
          head_commit_oid: obligation.target_candidate.head_commit_oid
        }
      },
      assessment:
    }
  end

  def compatibility_assessment_document(evidence_kind:, conclusion:, produced_at:)
    {
      evidence_kind:,
      producer: { name: "cucumber-external-verifier", version: "1.0.0" },
      run_id: "run-cuc-#{@obligation_prefix.downcase}-#{evidence_kind}",
      test_suite_digest: acceptance_digest("suite", evidence_kind),
      environment_digest: acceptance_digest("environment", evidence_kind),
      dependency_graph_digest: acceptance_digest("dependencies", evidence_kind),
      result_digest: acceptance_digest("result", evidence_kind, conclusion),
      conclusion:,
      findings: compatibility_findings(conclusion),
      produced_at:
    }
  end

  def compatibility_findings(conclusion)
    return [] if conclusion == "passed"

    [
      {
        code: "cucumber-#{conclusion.tr('_', '-')}",
        severity: conclusion == "failed" ? "error" : "warning",
        summary: "The external compatibility assessment concluded #{conclusion}."
      }
    ]
  end

  def acceptance_digest(*parts)
    Coordinator::Shared::CanonicalJson.new.sha256(parts)
  end

  def verification_obligation_history
    event_store.read(
      streams.verification_obligation(@obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Read::Contracts::VerificationObligationSourceEvent::EVENT_TYPES,
        maximum_count: 40,
        direction: :asc
      )
    )
  end

  def compatibility_evidence_events
    verification_obligation_history.select { _1.type == "VerificationEvidenceSubmitted" }
  end

  def verification_terminal_events
    verification_obligation_history.select do |event|
      event.type.in?(%w[VerificationObligationSatisfied VerificationObligationFailed])
    end
  end

  def project_verification_events(events, redeliver: false)
    expected_status =
      if events.any? { _1.type == "VerificationObligationSatisfied" }
        "satisfied"
      elsif events.any? { _1.type == "VerificationObligationFailed" }
        "failed"
      end
    expected_evidence = compatibility_evidence_events.length
    restart_read_model_subscriptions if redeliver && @live_subscription_sets&.key?(:read_models)
    await_read_model("Verification obligation #{@obligation_id} evidence to become available") do
      payload = candidate_obligation_page(
        obligation_id: @obligation_id,
        status: expected_status || "open"
      )
      item = payload.dig("data", "page", "items")&.find do |candidate|
        candidate.fetch("obligation_id") == @obligation_id
      end
      observed_evidence = item&.fetch("submitted_evidence", [])&.length || 0
      matches = item && observed_evidence >= expected_evidence &&
                (!expected_status || item.fetch("status") == expected_status)
      [ matches, payload ]
    end
  end

  def available_evidence_obligation(status: "open")
    candidate_obligation_page(obligation_id: @obligation_id, status:)
      .dig("data", "page", "items")
  end

  def assert_evidence_task_status(attempt, expected_status)
    assert_acceptance_equal("completed", attempt.dig(:state, "result", "status"), "Evidence Task status")
    assert_acceptance_equal(false, attempt.dig(:result, "isError"), "Evidence Task error")
    assert_acceptance_equal("ok", attempt.dig(:content, "status"), "Evidence command status")
    assert_acceptance_equal(
      expected_status,
      attempt.dig(:content, "data", "status"),
      "Evidence obligation status"
    )
  end

  def assert_evidence_task_error(attempt, code)
    assert_acceptance_equal("completed", attempt.dig(:state, "result", "status"), "Denied Task status")
    assert_acceptance_equal(true, attempt.dig(:result, "isError"), "Denied Task error")
    assert_acceptance_equal(code, attempt.dig(:content, "data", "code"), "Denied evidence code")
  end

  def evidence_event_for(attempt)
    command_id = task_command_id(attempt.fetch(:task_id))
    compatibility_evidence_events.find do |event|
      event.metadata.fetch("command_id") == command_id
    end
  end

  def assert_evidence_task_tracing(attempt)
    submitted, started, task_completed = task_events(attempt.fetch(:task_id))
    evidence = evidence_event_for(attempt)
    command_id = task_command_id(attempt.fetch(:task_id))
    command_terminal = command_terminal_event(command_id)
    outcome = verification_terminal_events.find do |event|
      event.metadata.fetch("command_id") == command_id
    end
    assert_acceptance(evidence, "Traced evidence fact is missing")
    assert_acceptance(outcome, "Traced outcome fact is missing")
    assert_acceptance_equal("CommandSucceeded", command_terminal&.type, "Evidence command terminal")
    assert_acceptance_equal(started.id, evidence.causation_id, "Evidence immediate parent")
    assert_acceptance_equal(started.id, outcome.causation_id, "Outcome immediate parent")
    assert_acceptance_equal(started.id, command_terminal.causation_id, "Command terminal immediate parent")
    assert_acceptance_equal(command_terminal.id, task_completed.causation_id, "Task completion parent")
    assert_acceptance_equal(
      [ submitted.correlation_id ],
      [ submitted, started, evidence, outcome, command_terminal, task_completed ].map(&:correlation_id).uniq,
      "Evidence Task correlation"
    )
    assert_acceptance(
      [ evidence, outcome, command_terminal ].none? { _1.metadata.key?("correlation_id") },
      "Application metadata duplicates correlation"
    )
  end
end

World(VerificationEvidenceOutcomeAcceptanceWorld)

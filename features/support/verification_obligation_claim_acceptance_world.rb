# frozen_string_literal: true

module VerificationObligationClaimAcceptanceWorld
  def prepare_open_verification_obligation(prefix:)
    prepare_candidate_obligation_coordination(prefix:)
    submit_candidate_obligation_pair
    activate_candidate_obligation_policy(level: "verification_gate")
    drive_candidate_policy_source(redeliver: true)
    assert_acceptance_equal(1, candidate_obligation_events.length, "Open verification obligation")
  end

  def submit_verification_obligation_claim(agent_id:, command_id:, duration:)
    arguments = {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      obligation_id: @obligation_id,
      claim_duration_seconds: duration
    }
    response = call_tool("verification_obligation_claim", arguments)
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "verification_obligation_claim did not return a Task handle")
    {
      agent_id:,
      command_id:,
      arguments:,
      task_id:,
      submitted_response: response
    }
  end

  def execute_verification_obligation_claim(attempt)
    execute_task(attempt.fetch(:task_id))
    attempt[:state] = task_request("tasks/get", attempt.fetch(:task_id))
    attempt[:result] = attempt.dig(:state, "result", "result")
    attempt[:content] = attempt.dig(:result, "structuredContent")
    attempt
  end

  def verification_obligation_claim_events
    event_store.read(
      streams.verification_obligation(@obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationClaimed" ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def project_verification_obligation_claims(redeliver: false)
    claim = verification_obligation_claim_events.last
    assert_acceptance(claim, "Verification obligation #{@obligation_id} has no claim fact")
    restart_read_model_subscriptions if redeliver && @live_subscription_sets&.key?(:read_models)
    await_read_model("Verification obligation #{@obligation_id} claim to become available") do
      payload = candidate_obligation_page(obligation_id: @obligation_id)
      item = payload.dig("data", "page", "items")&.find do |candidate|
        candidate.fetch("obligation_id") == @obligation_id
      end
      [ item&.dig("claim", "fencing_token") == claim.data.fetch("fencing_token"), payload ]
    end
  end

  def available_verification_obligation(**filters)
    content = candidate_obligation_page(obligation_id: @obligation_id, **filters)
    [ content, content.dig("data", "page") ]
  end
end

World(VerificationObligationClaimAcceptanceWorld)

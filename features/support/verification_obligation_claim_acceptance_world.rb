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

  def execute_verification_obligation_claim(attempt, at:)
    Timecop.freeze(Time.iso8601(at)) { execute_task(attempt.fetch(:task_id)) }
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
    projector = Coordinator::Container["projectors.verification_obligations_v1"]
    verification_obligation_claim_events.each do |event|
      projector.call(event)
      projector.call(event) if redeliver
    end
  end

  def available_verification_obligation(at:, **filters)
    content = Timecop.freeze(Time.iso8601(at)) do
      candidate_obligation_page(obligation_id: @obligation_id, **filters)
    end
    [ content, content.dig("data", "page") ]
  end
end

World(VerificationObligationClaimAcceptanceWorld)

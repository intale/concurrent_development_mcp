# frozen_string_literal: true

module VerificationObligationLifecycleAcceptanceWorld
  def submit_verification_obligation_waiver(user_id:, command_id:)
    obligation = candidate_obligation_payload
    arguments = {
      command_id:,
      actor: { kind: "user", id: user_id },
      obligation_id: @obligation_id,
      obligation_validity_input_digest: obligation.validity_input_digest,
      reason: {
        code: "accepted_risk",
        summary: "User accepts this exact recorded coordination risk."
      }
    }
    response = call_tool("verification_obligation_waive", arguments)
    @waiver_attempt = {
      command_id:,
      arguments:,
      task_id: response.dig("result", "taskId")
    }
  end

  def execute_verification_obligation_waiver
    execute_task(@waiver_attempt.fetch(:task_id))
    @waiver_attempt[:state] = task_request("tasks/get", @waiver_attempt.fetch(:task_id))
    @waiver_attempt[:result] = @waiver_attempt.dig(:state, "result", "result")
    @waiver_attempt[:content] = @waiver_attempt.dig(:result, "structuredContent")
  end

  def verification_obligation_lifecycle_events
    event_store.read(
      streams.verification_obligation(@obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Read::Contracts::VerificationObligationSourceEvent::EVENT_TYPES,
        maximum_count: 40,
        direction: :asc
      )
    )
  end

  def project_verification_obligation_lifecycle
    projector = Coordinator::Container["projectors.verification_obligations_v1"]
    verification_obligation_lifecycle_events.drop(1).each do |event|
      projector.call(event)
      projector.call(event)
    end
  end

  def correct_candidate_obligation_policy
    suffix = "lifecycle-correction"
    message_id = "M-CUC-OBL-LIFECYCLE-CORRECTION"
    interpretation_id = "I-CUC-OBL-LIFECYCLE-CORRECTION"
    decision_id = @obligation_policy.fetch(:decision_id)
    submit_and_execute(
      "guidance_record",
      command_id: "cmd-cuc-obligation-lifecycle-guidance",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-CUC-OBL-LIFECYCLE-CORRECTION",
      source: "mcp_client",
      text: "Correct the Candidate verification policy.",
      anchors: {
        repository_ids: [],
        change_set_id: @obligation_change_set_id,
        work_item_id: nil,
        attempt_id: nil
      }
    )
    proposal = candidate_obligation_policy_proposal(
      suffix:,
      message_id:,
      interpretation_id:,
      level: "merge_gate"
    )
    proposal.fetch(:proposed_decision).fetch(:relations)[:corrects] = [ decision_id ]
    proposal.fetch(:proposed_decision).fetch(:value)[:items] = [ "combined_tests" ]
    submit_and_execute("decision_interpretation_propose", **proposal)
    submit_and_execute(
      "decision_interpretation_adjudicate",
      command_id: "cmd-cuc-obligation-lifecycle-adjudicate",
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: message_id,
      interpretation_id:,
      action: "accept",
      rationale: {
        code: "user_confirmed",
        summary: "The user confirmed the corrected Candidate policy."
      },
      clarification: nil
    )
    submit_and_execute(
      "decision_correct",
      command_id: "cmd-cuc-obligation-lifecycle-correct",
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id:,
      expected_head: @obligation_policy.fetch(:head).event.to_h,
      rationale: {
        code: "normalization_corrected",
        summary: "Apply the accepted Candidate policy correction."
      }
    )
    @corrected_partition_event = candidate_policy_partition_events.last
  end

  def drive_verification_obligation_validity(redeliver: true)
    manager = Coordinator::Container["process_managers.verification_obligation_validity"]
    manager.call(@corrected_partition_event)
    manager.call(@corrected_partition_event) if redeliver
    loop do
      checkpoint = verification_obligation_validity_scan_events.find do |event|
        %w[
          VerificationObligationValidityScanStarted
          VerificationObligationValidityScanProgressed
        ].include?(event.type)
      end
      break unless checkpoint

      manager.call(checkpoint)
      manager.call(checkpoint) if redeliver
      break if verification_obligation_validity_scan_events.any? do |event|
        event.type == "VerificationObligationValidityScanCompleted"
      end
    end
  end

  def verification_obligation_validity_scan_events
    identity = Coordinator::Write::VerificationObligationValidityScans::IdentityBuilder.new
    scan_id = identity.scan(
      superseding_partition_event: candidate_obligation_event_reference(@corrected_partition_event),
      rule_version: "verification-obligation-validity/v1"
    )
    event_store.read_grouped(
      streams.verification_obligation_validity_scan(scan_id),
      Coordinator::Write::EventQueries::VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATE
    )
  end
end

World(VerificationObligationLifecycleAcceptanceWorld)

# frozen_string_literal: true

Given("an accepted Operation Batch whose next process command identity is known") do
  prepare_batch_process_identity
end

Given("a ReleaseSet whose next lifecycle command identity is known") do
  prepare_release_process_identity
end

When("an agent submits that internal command identity through a public mutation") do
  submit_reserved_internal_identity
end

Then("MCP rejects the input before allocating a Task") do
  result = @reserved_internal_response.fetch("result")
  assert_acceptance_equal("complete", result.fetch("resultType"), "Immediate result type")
  assert_acceptance_equal(true, result.fetch("isError"), "Reserved command identity")
  assert_acceptance_equal(
    [],
    task_events_for_request(
      @reserved_internal_command_id,
      actor: { kind: "agent", id: "identity-preemption-agent" }
    ),
    "Task facts"
  )
  assert_acceptance_equal([], command_events(@reserved_internal_command_id), "Premature command facts")
end

Then("the live Batch Saga eventually completes normally") do
  finish_paused_saga
  events = operation_batch_events
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchItemSucceeded" }, "Batch outcome")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchCompleted" }, "Batch completion")
  outcome = events.find { _1.type == "OperationBatchItemSucceeded" }
  assert_acceptance_equal(@reserved_internal_command_id, outcome.metadata.fetch("command_id"), "Process command")
end

Then("the live ReleaseSet Saga eventually reaches its valid terminal outcome") do
  finish_paused_saga
  events = release_set_lifecycle_events(@release_set_id)
  completion = events.select { _1.type == "ReleaseSetCompleted" }.sole
  assert_acceptance_equal("compensated", release_set_payload(completion).outcome, "ReleaseSet outcome")
  request = events.find { _1.type == "ReleaseSetCompensationRequested" }
  assert_acceptance_equal(@reserved_internal_command_id, request.metadata.fetch("command_id"), "Process command")
  assert_acceptance_equal([ events.first.correlation_id ], events.map(&:correlation_id).uniq, "Saga correlation")
end

Given("a target command completed before an Operation Batch under another correlation") do
  prepare_prior_target_for_batch_replay
end

When("a live Batch processes an item containing the exact prior command") do
  process_prior_target_through_batch
end

Then("the item has one successful outcome") do
  outcomes = @batch_history_after_redelivery.select do |event|
    event.type == "OperationBatchItemSucceeded"
  end
  assert_acceptance_equal(1, outcomes.length, "Batch item outcomes")
  creation = @batch_history_after_redelivery.find { _1.type == "OperationBatchCreated" }
  process_step = process_step_event(
    source_event: creation,
    process_name: "operation-batch-runner",
    step_name: "record-item-outcome",
    subject_kind: "operation-batch-item",
    subject_id: "#{@operation_batch_id}:0"
  )
  assert_acceptance(process_step, "Replayed Batch item ProcessStep is missing")
  assert_acceptance_equal(process_step.id, outcomes.sole.causation_id, "Replayed item causation")
  assert_acceptance_equal(creation.id, process_step.causation_id, "Replayed ProcessStep causation")
  assert_acceptance(
    @prior_target_terminal.correlation_id != creation.correlation_id,
    "The prior target and Batch unexpectedly share one correlation"
  )
end

Then("every event in the Batch Saga has the Batch correlation identifier") do
  creation = @batch_history_after_redelivery.find { _1.type == "OperationBatchCreated" }
  assert_acceptance_equal(
    [ creation.correlation_id ],
    @batch_history_after_redelivery.map(&:correlation_id).uniq,
    "Batch correlations"
  )
end

Then("duplicate source delivery produces no additional logical outcome") do
  assert_acceptance_equal(
    @batch_history_before_redelivery.map(&:id),
    @batch_history_after_redelivery.map(&:id),
    "Batch history after redelivery"
  )
  assert_acceptance_equal(
    1,
    @batch_history_after_redelivery.count { _1.type == "OperationBatchCompleted" },
    "Batch terminal facts"
  )
end

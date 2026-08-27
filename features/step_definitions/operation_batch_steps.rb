# frozen_string_literal: true

When("the agent submits a batch of {int} independent Skill publications") do |count|
  @operation_batch_id = SecureRandom.uuid_v7
  items = count.times.map do |index|
    batch_skill_item(index:, name: "batch-skill-#{index}")
  end
  submit_skill_batch(items, pause_at: "operation_batch_page")
end

When("the agent submits two competing initial revisions in one Skill batch") do
  @operation_batch_id = SecureRandom.uuid_v7
  items = [
    batch_skill_item(index: 0, name: "competing-skill", expected_revision: 0),
    batch_skill_item(index: 1, name: "competing-skill", expected_revision: 0)
  ]
  submit_skill_batch(items, pause_at: "operation_batch_page_start")
end

Then("the Batch Task durably accepts all {int} items") do |count|
  outcome = @operation_batch_task.dig("result", "result", "structuredContent")
  assert_acceptance_equal("completed", @operation_batch_task.dig("result", "status"), "Batch Task status")
  assert_acceptance_equal("accepted", outcome.dig("data", "status"), "Batch acceptance")
  assert_acceptance_equal(count, outcome.dig("data", "total"), "Accepted item count")
  assert_acceptance_equal(1, operation_batch_events.count { _1.type == "OperationBatchCreated" }, "Creation facts")
end

Then("the Batch Task durably accepts both items") do
  step("the Batch Task durably accepts all 2 items")
end

When("the process workers restart after the first durable Batch page") do
  restart_operation_batch_after_page
end

Then("the Batch has {int} successes, no rejection, and one terminal completion") do |count|
  events = operation_batch_events
  assert_acceptance_equal(count, events.count { _1.type == "OperationBatchItemSucceeded" }, "Success facts")
  assert_acceptance_equal(0, events.count { _1.type == "OperationBatchItemRejected" }, "Rejected facts")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchCompleted" }, "Completion facts")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchContinuationRequested" }, "Continuation facts")
end

When("the Batch creation reaches the read side while item execution is paused") do
  await_contention_evidence
  creation = operation_batch_events.find { _1.type == "OperationBatchCreated" }
  project_operation_batch([ creation ])
end

Then("the available Batch remains running with no observed item outcome") do
  view = operation_batch_view
  assert_acceptance_equal("running", view.fetch("status"), "Available running status")
  assert_acceptance_equal(0, view.fetch("succeeded"), "Available successes")
  assert_acceptance_equal(0, view.fetch("rejected"), "Available rejections")
  assert_acceptance(!view.key?("fresh"), "Batch response must not expose a freshness gate")
end

When("the Batch decision boundary is released and terminal facts reach the read side") do
  release_contention_barrier
  await_operation_batch_terminal
  project_operation_batch(operation_batch_events)
end

Then("the available Batch completes with one success and one rejection") do
  view = operation_batch_view
  assert_acceptance_equal("completed_with_errors", view.fetch("status"), "Terminal Batch status")
  assert_acceptance_equal(1, view.fetch("succeeded"), "Terminal successes")
  assert_acceptance_equal(1, view.fetch("rejected"), "Terminal rejections")
  assert_acceptance_equal(0, view.fetch("not_run"), "Terminal unprocessed count")
end

When("the first Batch process page completes") do
  await_contention_evidence
end

Then("{int} item successes and one continuation are durable") do |count|
  events = operation_batch_events
  assert_acceptance_equal(count, events.count { _1.type == "OperationBatchItemSucceeded" }, "Item successes")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchContinuationRequested" }, "Continuations")
  assert_acceptance_equal(0, events.count { _1.type == "OperationBatchCompleted" }, "Premature completion")
end

When("the agent requests cooperative Batch cancellation") do
  @operation_batch_cancel_task_id = submit_and_execute(
    "operation_batch_cancel",
    command_id: "cmd-cuc-batch-cancel-#{@operation_batch_id}",
    actor: { kind: "agent", id: "import-agent" },
    batch_id: @operation_batch_id
  )
  @operation_batch_cancel_task = task_request("tasks/get", @operation_batch_cancel_task_id)
end

Then("the cancellation Task succeeds without undoing completed items") do
  result = @operation_batch_cancel_task.dig("result", "result")
  assert_acceptance_equal("completed", @operation_batch_cancel_task.dig("result", "status"), "Cancel Task")
  assert_acceptance_equal(false, result.fetch("isError"), "Cancel tool error")
  assert_acceptance_equal(
    50,
    operation_batch_events.count { _1.type == "OperationBatchItemSucceeded" },
    "Retained successes"
  )
end

When("the pending Batch continuation observes cancellation") do
  release_contention_barrier
  await_operation_batch_terminal
end

Then("the Batch is cancelled with {int} successes and one item not run") do |count|
  events = operation_batch_events
  cancelled = events.find { _1.type == "OperationBatchCancelled" }
  assert_acceptance(cancelled, "The Batch has no terminal cancellation fact")
  assert_acceptance_equal(count, cancelled.data.fetch("succeeded"), "Cancelled successes")
  assert_acceptance_equal(0, cancelled.data.fetch("rejected"), "Cancelled rejections")
  assert_acceptance_equal(1, cancelled.data.fetch("not_run"), "Cancelled remainder")
  project_operation_batch(events)
  view = operation_batch_view
  assert_acceptance_equal("cancelled", view.fetch("status"), "Available cancelled status")
  assert_acceptance_equal(count, view.fetch("succeeded"), "Available successes")
  assert_acceptance_equal(1, view.fetch("not_run"), "Available unprocessed count")
end

# frozen_string_literal: true

When("the agent submits a batch of {int} independent Skill publications") do |count|
  @operation_batch_id = SecureRandom.uuid_v7
  items = count.times.map do |index|
    batch_skill_item(index:, name: "batch-skill-#{index}")
  end
  submit_skill_batch(items)
end

When("the agent submits two competing initial revisions in one Skill batch") do
  @operation_batch_id = SecureRandom.uuid_v7
  items = [
    batch_skill_item(index: 0, name: "competing-skill", expected_revision: 0),
    batch_skill_item(index: 1, name: "competing-skill", expected_revision: 0)
  ]
  submit_skill_batch(items)
end

Then("the Batch Task accepts all {int} items before target execution") do |count|
  outcome = @operation_batch_task.dig("result", "result", "structuredContent")
  assert_acceptance_equal("completed", @operation_batch_task.dig("result", "status"), "Batch Task status")
  assert_acceptance_equal("accepted", outcome.dig("data", "status"), "Batch acceptance")
  assert_acceptance_equal(count, outcome.dig("data", "total"), "Accepted item count")
  assert_acceptance_equal([ "OperationBatchCreated" ], operation_batch_events.map(&:type), "Pre-Saga facts")
end

Then("the Batch Task accepts both items before target execution") do
  step("the Batch Task accepts all 2 items before target execution")
end

When("the Batch creation is delivered twice and all continuations run") do
  run_operation_batch_sources(redeliver_creation: true)
end

When("the Batch Saga processes the competing revisions") do
  run_operation_batch_sources
end

Then("the Batch has {int} successes, no rejection, and one terminal completion") do |count|
  events = operation_batch_events
  assert_acceptance_equal(count, events.count { _1.type == "OperationBatchItemSucceeded" }, "Success facts")
  assert_acceptance_equal(0, events.count { _1.type == "OperationBatchItemRejected" }, "Rejected facts")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchCompleted" }, "Completion facts")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchContinuationRequested" }, "Continuation facts")
end

When("only the first Batch progress facts reach the read side") do
  events = operation_batch_events
  project_operation_batch(
    [
      events.find { _1.type == "OperationBatchCreated" },
      events.find { _1.type == "OperationBatchItemSucceeded" }
    ]
  )
end

Then("the available Batch remains running with one observed success") do
  view = operation_batch_view
  assert_acceptance_equal("running", view.fetch("status"), "Available running status")
  assert_acceptance_equal(1, view.fetch("succeeded"), "Available successes")
  assert_acceptance_equal(0, view.fetch("rejected"), "Available rejections")
  assert_acceptance(!view.key?("fresh"), "Batch response must not expose a freshness gate")
end

When("the remaining Batch facts reach the read side") do
  project_operation_batch(operation_batch_events)
end

Then("the available Batch completes with one success and one rejection") do
  view = operation_batch_view
  assert_acceptance_equal("completed_with_errors", view.fetch("status"), "Terminal Batch status")
  assert_acceptance_equal(1, view.fetch("succeeded"), "Terminal successes")
  assert_acceptance_equal(1, view.fetch("rejected"), "Terminal rejections")
  assert_acceptance_equal(0, view.fetch("not_run"), "Terminal unprocessed count")
end

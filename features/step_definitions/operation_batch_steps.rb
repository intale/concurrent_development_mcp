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

Then("the complete normalized manifest and outcomes are recoverable in bounded pages using only the Batch ID") do
  project_operation_batch(
    operation_batch_events,
    timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS
  )
  manifest = operation_batch_manifest(limit: 20)
  assert_acceptance_equal(3, manifest.fetch(:pages).length, "Bounded manifest pages")
  assert_acceptance_equal(
    @submitted_operation_batch_items,
    manifest.fetch(:items).map { _1.fetch("arguments") },
    "Normalized manifest arguments"
  )
  assert_acceptance_equal(
    Array.new(51, "succeeded"),
    manifest.fetch(:items).map { _1.fetch("status") },
    "Manifest outcomes"
  )
end

Then("page-boundary redelivery leaves one marked outcome per item") do
  outcomes = operation_batch_events.select { _1.type == "OperationBatchItemSucceeded" }
  assert_acceptance_equal((0...51).to_a, outcomes.map { _1.data.fetch("index") }.sort, "Unique item outcomes")
  outcomes.each do |event|
    marker = "batch-item:#{@operation_batch_id}:#{event.data.fetch("index")}"
    assert_acceptance(event.markers.include?(marker), "Outcome #{event.id} is missing #{marker}")
  end
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

Then("the available Batch exposes accepted cancellation before terminal completion") do
  view = await_read_model("Operation Batch #{@operation_batch_id} to expose accepted cancellation") do
    observed = operation_batch_view
    matched = observed&.fetch("status", nil) == "cancelling" &&
              observed.dig("cancellation", "event", "type") == "OperationBatchCancellationRequested"
    [ matched, observed ]
  end
  assert_acceptance_equal(1, view.fetch("pending"), "Pending cancellation remainder")
  assert_acceptance_equal(0, view.fetch("not_run"), "Premature not-run count")
  assert_acceptance_equal(nil, view.fetch("terminal"), "Premature terminal evidence")
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
  project_operation_batch(
    events,
    timeout_seconds: LiveSubscriptions::HIGH_VOLUME_TIMEOUT_SECONDS
  )
  view = operation_batch_view
  assert_acceptance_equal("cancelled", view.fetch("status"), "Available cancelled status")
  assert_acceptance_equal(count, view.fetch("succeeded"), "Available successes")
  assert_acceptance_equal(1, view.fetch("not_run"), "Available unprocessed count")
end

When("the agent resubmits only the not-run manifest items") do
  resubmit_not_run_items
end

Then("the resumed Batch succeeds once without replaying the completed prefix") do
  resumed = operation_batch_events(batch_id: @resumed_operation_batch_id)
  assert_acceptance_equal(1, resumed.count { _1.type == "OperationBatchItemSucceeded" }, "Resumed success facts")
  assert_acceptance_equal(0, resumed.count { _1.type == "OperationBatchItemRejected" }, "Resumed rejection facts")
  assert_acceptance_equal(1, resumed.count { _1.type == "OperationBatchCompleted" }, "Resumed terminal facts")

  resumed_manifest = operation_batch_manifest(batch_id: @resumed_operation_batch_id)
  resumed_command_ids = resumed_manifest.fetch(:items).map { _1.fetch("command_id") }
  assert_acceptance_equal(1, resumed_command_ids.length, "Resumed manifest size")
  assert_acceptance(
    (@completed_prefix_command_ids & resumed_command_ids).empty?,
    "The completed prefix was included in the resumed Batch"
  )
  original = operation_batch_manifest(batch_id: @cancelled_operation_batch_id)
  assert_acceptance_equal(50, original.fetch(:items).count { _1.fetch("status") == "succeeded" }, "Original prefix")
  assert_acceptance_equal(1, original.fetch(:items).count { _1.fetch("status") == "not_run" }, "Original remainder")
end

When("the agent publishes equivalent Unicode Skill assets through single and Batch tools") do
  @batch_parity_text = "Säker samordning — λ\n"
  @batch_parity_asset = {
    path: "docs/policy.txt",
    executable: false,
    content: {
      encoding: "utf-8",
      media_type: "text/plain",
      text: @batch_parity_text
    }
  }
  @batch_parity_single = publish_skill_task(
    name: "semantic-single",
    scope: "project:cucumber-batch",
    command_id: "cmd-cuc-semantic-single",
    expected_revision: 0,
    instructions: "Apply the Unicode policy.",
    assets: [ @batch_parity_asset ]
  )

  @operation_batch_id = SecureRandom.uuid_v7
  @batch_parity_item = batch_skill_item(index: 0, name: "semantic-batch").merge(
    instructions: "Apply the Unicode policy.",
    assets: [ @batch_parity_asset ]
  )
  submit_skill_batch([ @batch_parity_item ])
  await_operation_batch_terminal
end

Then("both Skill commands succeed with semantic version 2 facts") do
  assert_acceptance_equal("ok", @batch_parity_single.fetch(:outcome).fetch("status"), "Single outcome")
  batch_outcomes = operation_batch_events.select { _1.type == "OperationBatchItemSucceeded" }
  assert_acceptance_equal(1, batch_outcomes.length, "Batch outcomes")

  facts = [ "semantic-single", "semantic-batch" ].map do |name|
    skill_events(name:, scope: "project:cucumber-batch").sole
  end
  assert_acceptance_equal([ 2, 2 ], facts.map { _1.metadata.fetch("schema_version") }, "Fact schemas")
  contents = facts.map { _1.data.fetch("assets").sole.fetch("content") }
  assert_acceptance_equal(1, contents.uniq.length, "Single/Batch semantic content")
  assert_acceptance_equal(@batch_parity_text, contents.first.fetch("text"), "Persisted Unicode text")
  assert_acceptance(!contents.first.key?("base64"), "Persisted Unicode content exposed Base64")
end

Then("the Batch manifest returns the original text-first ordinary command arguments") do
  project_operation_batch(operation_batch_events)
  arguments = operation_batch_manifest.fetch(:items).sole.fetch("arguments")
  expected = JSON.parse(JSON.generate(@batch_parity_item))
  assert_acceptance_equal(expected, arguments, "Batch ordinary command arguments")
  content = arguments.fetch("assets").sole.fetch("content")
  assert_acceptance_equal(@batch_parity_text, content.fetch("text"), "Manifest Unicode text")
  assert_acceptance(!content.key?("base64"), "Manifest Unicode content exposed Base64")
  assert_acceptance(
    (content.keys & %w[content_sha256 byte_size]).empty?,
    "Manifest exposed server-derived content fields"
  )
end

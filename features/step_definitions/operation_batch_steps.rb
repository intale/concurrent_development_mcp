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

When("the agent submits two independent batches and one ordinary publication sharing an identical request") do
  stop_process_subscriptions
  shared = batch_skill_item(index: 0, name: "shared-request-skill").merge(command_id: "cmd-cuc-shared-publication")
  ordinary = call_tool("skill_publish", shared, client_id: "import-agent")
  @shared_publication_task_id = ordinary.dig("result", "taskId")
  @shared_publication_command_id = task_command_id(@shared_publication_task_id)
  @shared_batch_submissions = 2.times.map do |index|
    batch_id = SecureRandom.uuid_v7
    independent = batch_skill_item(index: index + 1, name: "independent-#{index}")
    response = call_tool("skill_publish_batch", {
      command_id: "cmd-cuc-shared-batch-#{index}", actor: { kind: "agent", id: "import-agent" },
      batch_id:, items: [ shared, independent ]
    }, client_id: "import-agent")
    { batch_id:, task_id: response.dig("result", "taskId") }
  end
  start_process_subscriptions
end

Then("all three Tasks succeed and both batches complete") do
  [ @shared_publication_task_id, *@shared_batch_submissions.map { _1.fetch(:task_id) } ].each do |task_id|
    result = await_task_terminal(task_id, client_id: "import-agent")
    assert_acceptance_equal(false, result.dig("result", "result", "isError"), "Submitted Task result")
  end
  @shared_batch_submissions.each do |submission|
    batch_id = submission.fetch(:batch_id)
    await_operation_batch_terminal(batch_id:)
    project_operation_batch(operation_batch_events(batch_id:), batch_id:)
    view = operation_batch_view(batch_id:)
    assert_acceptance_equal("completed", view.fetch("status"), "Independent Batch status")
    assert_acceptance_equal(2, view.fetch("succeeded"), "Independent Batch successes")
  end
end

Then("the shared request has one canonical publication and a success in each Batch") do
  command_events = event_store.read(
    streams.command(@shared_publication_command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY
  )
  assert_acceptance_equal(%w[CommandRegistered CommandSucceeded], command_events.map(&:type), "Canonical command history")
  @shared_batch_submissions.each do |submission|
    batch_id = submission.fetch(:batch_id)
    events = operation_batch_events(batch_id:)
    assignment = events.find { _1.type == "OperationBatchItemCommandAssigned" && _1.data.fetch("index").zero? }
    assert_acceptance_equal(@shared_publication_command_id, assignment.data.fetch("command_id"), "Shared canonical binding")
    items = eventually("shared Batch item receipt") do
      observed = operation_batch_view(batch_id:).fetch("items")
      [ observed.first.dig("result", "status") == "ok", observed ]
    end
    assert_acceptance_equal("cmd-cuc-shared-publication", items.first.dig("result", "command_id"), "Shared client receipt")
  end
end

When("the agent completes an original Batch request and accepts another Batch with changed input under that request") do
  @operation_batch_id = SecureRandom.uuid_v7
  original = batch_skill_item(index: 0, name: "original-shared-request")
  submit_skill_batch([ original ])
  await_operation_batch_terminal
  @original_request_command_id = operation_batch_events.find { _1.type == "OperationBatchItemCommandAssigned" }.data.fetch("command_id")
  @operation_batch_id = SecureRandom.uuid_v7
  submit_skill_batch([
    original.merge(instructions: "Changed instructions under an existing request."),
    batch_skill_item(index: 1, name: "unrelated-success")
  ])
  await_operation_batch_terminal
  project_operation_batch(operation_batch_events)
end

Then("the second Batch completes with a durable request-reuse denial and an independent success") do
  view = operation_batch_view
  assert_acceptance_equal("completed_with_errors", view.fetch("status"), "Request reuse Batch status")
  assert_acceptance_equal(1, view.fetch("succeeded"), "Independent item success")
  assert_acceptance_equal(1, view.fetch("rejected"), "Request reuse denial")
  events = operation_batch_events
  rejection = events.select { _1.type == "OperationBatchItemRegistrationRejected" }.sole
  assert_acceptance_equal("command_id_reused", rejection.data.dig("error", "code"), "Durable binding denial")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchItemCommandAssigned" }, "Only independent item bound")
end

Then("the denied item has no fabricated canonical receipt") do
  item = operation_batch_view.fetch("items").first
  assert_acceptance_equal("rejected", item.fetch("status"), "Denied item status")
  assert_acceptance_equal("command_id_reused", item.dig("result", "status"), "Denied item result")
  assert_acceptance_equal(nil, item.dig("result", "receipt"), "Unregistered item receipt")
  events = event_store.read(streams.command(@original_request_command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  assert_acceptance_equal(%w[CommandRegistered CommandSucceeded], events.map(&:type), "Original request remains successful")
end

When("a one-item Batch pauses after its canonical assignment before target execution") do
  @operation_batch_id = SecureRandom.uuid_v7
  submit_skill_batch([ batch_skill_item(index: 0, name: "cancelled-after-assignment") ], pause_at: "operation_batch_item_assigned")
  await_contention_evidence
  @unexecuted_batch_command_id = operation_batch_events.find { _1.type == "OperationBatchItemCommandAssigned" }.data.fetch("command_id")
end

Then("the assigned item is not run and its canonical command has no terminal effect") do
  events = operation_batch_events
  assert_acceptance_equal(0, events.count { _1.type == "OperationBatchItemExecutionStarted" }, "No item started")
  assert_acceptance_equal(1, operation_batch_view.fetch("not_run"), "Assigned but unexecuted item")
  history = event_store.read(streams.command(@unexecuted_batch_command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  assert_acceptance_equal([ "CommandRegistered" ], history.map(&:type), "Unexecuted canonical history")
end

Then("the unexecuted canonical binding is reused successfully") do
  events = operation_batch_events
  assignment = events.select { _1.type == "OperationBatchItemCommandAssigned" }.sole
  assert_acceptance_equal(@unexecuted_batch_command_id, assignment.data.fetch("command_id"), "Resumed canonical binding")
  assert_acceptance_equal(1, operation_batch_view.fetch("succeeded"), "Resumed success")
  history = event_store.read(streams.command(@unexecuted_batch_command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  assert_acceptance_equal(%w[CommandRegistered CommandSucceeded], history.map(&:type), "Executed once after resubmission")
end

When("a one-item Batch pauses after its target commits before recording its outcome") do
  @operation_batch_id = SecureRandom.uuid_v7
  submit_skill_batch([ batch_skill_item(index: 0, name: "committed-before-outcome") ], pause_at: "operation_batch_item_outcome")
  await_contention_evidence
  events = operation_batch_events
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchItemExecutionStarted" }, "Committed item start")
  assert_acceptance_equal(0, events.count { _1.type == "OperationBatchItemSucceeded" }, "Outcome gap")
end

When("the process workers restart after the committed target boundary") do
  restart_operation_batch_after_page
  project_operation_batch(operation_batch_events)
end

Then("cancellation retains one committed success and no item not run") do
  view = operation_batch_view
  assert_acceptance_equal("cancelled", view.fetch("status"), "Cancelled Batch status")
  assert_acceptance_equal(1, view.fetch("succeeded"), "Retained committed success")
  assert_acceptance_equal(0, view.fetch("not_run"), "Committed item is not an unexecuted remainder")
  events = operation_batch_events
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchItemExecutionStarted" }, "One committed execution")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchItemSucceeded" }, "One outcome")
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchCancelled" }, "One terminal cancellation")
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
  completed = events.select { _1.type == "OperationBatchCompleted" }.sole
  assert_acceptance_equal({ "batch_id" => @operation_batch_id }, completed.data, "Lean completion fact")
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

Then("both child command results are independently available through MCP") do
  items = operation_batch_manifest.fetch(:items)
  items.each do |item|
    request_id = item.fetch("arguments").fetch("command_id")
    result = eventually("child command #{request_id} receipt") do
      result = call_tool("operation_get", { command_id: request_id }).dig("result", "structuredContent")
      [ result && result.fetch("status") != "not_found", result ]
    end
    assert_acceptance_equal(request_id, result.fetch("command_id"), "Child receipt identity")
    if item.fetch("status") == "succeeded"
      assert_acceptance_equal("ok", result.fetch("status"), "Child success receipt")
      types = result.dig("data", "emitted_events").map { _1.fetch("type") }
      assert_acceptance(types.include?("SkillRevisionPublished"), "Child receipt must include its Skill publication")
      assert_acceptance(types.none? { _1.start_with?("OperationBatch") }, "Parent batch facts must not be child output")
    else
      assert_acceptance_equal("skill_revision_conflict", result.dig("data", "code"), "Child conflict receipt")
    end
  end
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
    observed = operation_batch_view(limit: 1)
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

Then("the Batch history derives {int} successes and one item not run after cancellation") do |count|
  events = operation_batch_events
  cancelled = events.find { _1.type == "OperationBatchCancelled" }
  assert_acceptance(cancelled, "The Batch has no terminal cancellation fact")
  assert_acceptance_equal(
    { "batch_id" => @operation_batch_id },
    cancelled.data,
    "Lean cancellation fact"
  )
  counts = operation_batch_outcome_counts(events)
  assert_acceptance_equal(count, counts.fetch(:succeeded), "Cancelled successes")
  assert_acceptance_equal(0, counts.fetch(:rejected), "Cancelled rejections")
  assert_acceptance_equal(1, counts.fetch(:remaining), "Cancelled remainder")
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
  completed = resumed.select { _1.type == "OperationBatchCompleted" }.sole
  assert_acceptance_equal(
    { "batch_id" => @resumed_operation_batch_id },
    completed.data,
    "Lean resumed terminal fact"
  )

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

Then("both Skill commands succeed with semantic version 3 facts") do
  assert_acceptance_equal("ok", @batch_parity_single.fetch(:outcome).fetch("status"), "Single outcome")
  batch_outcomes = operation_batch_events.select { _1.type == "OperationBatchItemSucceeded" }
  assert_acceptance_equal(1, batch_outcomes.length, "Batch outcomes")

  publications = [ "semantic-single", "semantic-batch" ].map do |name|
    skill_events(name:, scope: "project:cucumber-batch").sole
  end
  assert_acceptance_equal([ 3, 3 ], publications.map { _1.metadata.fetch("schema_version") }, "Fact schemas")
  contents = [ "semantic-single", "semantic-batch" ].map do |name|
    skill_fact_events(name:, scope: "project:cucumber-batch")
      .select { _1.type == "SkillAssetContentDefined" }
      .sole
  end
  assert_acceptance_equal(
    1,
    contents.map { _1.data.fetch("content") }.uniq.length,
    "Single/Batch semantic content"
  )
  assert_acceptance_equal([ "utf-8", "utf-8" ], contents.map { _1.metadata.fetch("encoding") }, "Content encodings")
  assert_acceptance_equal(
    [ @batch_parity_text, @batch_parity_text ],
    contents.map { _1.data.fetch("content") },
    "Persisted Unicode text"
  )
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

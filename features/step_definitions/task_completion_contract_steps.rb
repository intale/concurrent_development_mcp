# frozen_string_literal: true

Given("both read projection sets are stopped") do
  stop_read_model_subscriptions
  stop_task_result_subscriptions
end

When("a clean agent creates a ChangeSet and waits only for its Task") do
  @contract_request = { command_id: "task-contract-create", actor: { kind: "agent", id: "clean-agent" },
    change_set_id: "task-contract-CS", goal: "Trust authoritative mutation receipts",
    acceptance_criteria: [ "Completion does not require entity read-back" ] }
  acceptance = call_tool("change_set_create", @contract_request, client_id: "clean-agent")
  @contract_task_id = acceptance.dig("result", "taskId")
  assert_acceptance(acceptance.dig("result", "statusMessage").include?("request is durably recorded"), "Acceptance note")
  start_process_subscriptions
  @contract_terminal = await_task_terminal(@contract_task_id, client_id: "clean-agent", project_task_results: false)
end

Then("the terminal receipt confirms durable facts and says no read-back is required") do
  result = @contract_terminal.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Successful Task result")
  completion = result.dig("structuredContent", "completion")
  assert_acceptance_equal("committed", completion.fetch("effects"), "Durable facts")
  assert_acceptance_equal(false, completion.fetch("read_back_required"), "Read-back requirement")
  assert_acceptance(result.dig("structuredContent", "summary").include?("No read-back is needed"), "Model-visible explanation")
  assert_acceptance(result.fetch("content").any? { _1.fetch("text").include?("No read-back is needed") }, "Text-only client explanation")
end

Then("the entity projection can still report not found without requiring another creation") do
  view = call_tool("coord_context", { change_set_id: @contract_request.fetch(:change_set_id) }).dig("result", "structuredContent")
  assert_acceptance_equal("not_found", view.fetch("status"), "Available stale absence")
  assert_acceptance_equal("completed", task_request("tasks/get", @contract_task_id).dig("result", "status"), "Task remains terminal")
end

When("another client replays the exact original request") do
  replay = call_tool("change_set_create", @contract_request, client_id: "replacement-agent")
  assert_acceptance_equal(@contract_task_id, replay.dig("result", "taskId"), "Original durable handle")
  assert_acceptance_equal("completed", replay.dig("result", "status"), "Actual durable Task status on replay")
  @contract_replayed_terminal = task_request("tasks/get", @contract_task_id, client_id: "replacement-agent")
end

Then("the original Task returns the identical authoritative outcome") do
  assert_acceptance_equal(@contract_terminal.fetch("result"), @contract_replayed_terminal.fetch("result"), "Stable terminal outcome")
end

Then("the requested ChangeSet facts were produced once without starting a projector") do
  events = event_store.read_grouped(streams.change_set(@contract_request.fetch(:change_set_id)), Coordinator::Write::EventQueries::CHANGE_SET_EXISTENCE)
  assert_acceptance_equal(1, events.count { _1.type == "ChangeSetCreated" }, "Creation count")
  assert_acceptance(!subscription_set_started?(:read_models) && !subscription_set_started?(:task_results), "No projection sets were started")
end

When("another agent requests the same ChangeSet using a new command") do
  acceptance = call_tool("change_set_create", @contract_request.merge(command_id: "task-contract-denied", actor: { kind: "agent", id: "other-agent" }))
  @contract_denial = await_task_terminal(acceptance.dig("result", "taskId"), project_task_results: false)
end

Then("the denied Task completes with no target effects and no read-back requirement") do
  assert_acceptance_equal("completed", @contract_denial.dig("result", "status"), "Protocol completion")
  result = @contract_denial.dig("result", "result")
  assert_acceptance_equal(true, result.fetch("isError"), "Business denial")
  assert_acceptance_equal("none", result.dig("structuredContent", "completion", "effects"), "Target effects")
  assert_acceptance_equal(false, result.dig("structuredContent", "completion", "read_back_required"), "Read-back requirement")
end

When("an agent submits a two-item Skill Batch with execution paused") do
  @operation_batch_id = SecureRandom.uuid_v7
  submit_skill_batch([ batch_skill_item(index: 0, name: "contract-batch-skill"),
    batch_skill_item(index: 1, name: "contract-batch-skill") ], pause_at: "operation_batch_page_start")
end

Then("the accepted Batch Task remains working and explains that effects are not confirmed") do
  state = task_request("tasks/get", @operation_batch_task_id, client_id: "import-agent").fetch("result")
  assert_acceptance_equal("working", state.fetch("status"), "Unsettled Batch Task")
  assert_acceptance(state.fetch("statusMessage").include?("requested effects are not yet confirmed"), "Acceptance guarantee")
  assert_acceptance(!state.key?("result"), "No terminal item result is fabricated")
end

When("the Batch is released without starting any read projection") do
  release_contention_barrier
  @contract_batch_terminal = await_task_terminal(@operation_batch_task_id, client_id: "import-agent", project_task_results: false)
end

Then("its Task reports one success and one rejection as a partial failure") do
  result = @contract_batch_terminal.dig("result", "result")
  assert_acceptance_equal(true, result.fetch("isError"), "Mixed Batch tool error")
  details = result.dig("structuredContent", "data", "details")
  assert_acceptance_equal(1, details.fetch("succeeded"), "Retained success")
  assert_acceptance_equal(1, details.fetch("rejected"), "Rejected item")
  assert_acceptance_equal(0, details.fetch("failed"), "Execution failures")
  assert_acceptance_equal(0, details.fetch("not_run"), "Unexecuted items")
  assert_acceptance_equal("partial", result.dig("structuredContent", "completion", "effects"), "Partial effects")
  assert_acceptance(result.dig("structuredContent", "summary").include?("not rolled back"), "No rollback claim")
end

Then("the successful publication remains durable without any projected Skill") do
  events = operation_batch_events
  assert_acceptance_equal(1, events.count { _1.type == "OperationBatchItemSucceeded" }, "Successful item fact")
  assert_acceptance_equal("not_found", call_tool("skill_get", { name: "contract-batch-skill", scope: "project:cucumber-batch" }).dig("result", "structuredContent", "status"), "Unobserved Skill projection")
  assert_acceptance(!subscription_set_started?(:read_models) && !subscription_set_started?(:task_results), "No projection sets were needed")
end

When("the agent cancels the paused Batch without reading its projection") do
  acceptance = call_tool("operation_batch_cancel", { command_id: "task-contract-cancel",
    actor: { kind: "agent", id: "import-agent" }, batch_id: @operation_batch_id }, client_id: "import-agent")
  @contract_cancel_terminal = await_task_terminal(acceptance.dig("result", "taskId"), client_id: "import-agent", project_task_results: false)
end

Then("the cancellation Task confirms only the durable cancellation request") do
  result = @contract_cancel_terminal.dig("result", "result")
  assert_acceptance_equal(false, result.fetch("isError"), "Cancellation request accepted")
  assert_acceptance_equal("request", result.dig("structuredContent", "completion", "scope"), "Only cancellation request scope")
  assert_acceptance_equal("working", task_request("tasks/get", @operation_batch_task_id, client_id: "import-agent").dig("result", "status"), "Original Batch is still processing")
end

Then("the original Batch Task reports cancellation with two not-run items and no target effects") do
  result = @contract_batch_terminal.dig("result", "result")
  assert_acceptance_equal(true, result.fetch("isError"), "Cancelled import result")
  assert_acceptance_equal("cancelled", result.dig("structuredContent", "completion", "outcome"), "Settled cancelled import")
  assert_acceptance_equal("none", result.dig("structuredContent", "completion", "effects"), "No target effects")
  details = result.dig("structuredContent", "data", "details")
  assert_acceptance_equal([ 0, 0, 0, 2 ], details.values_at("succeeded", "rejected", "failed", "not_run"), "Partitioned cancellation counts")
  assert_acceptance_equal(false, result.dig("structuredContent", "completion", "read_back_required"), "No persistence read-back")
  assert_acceptance(!subscription_set_started?(:read_models) && !subscription_set_started?(:task_results), "Neither projection set is needed")
end

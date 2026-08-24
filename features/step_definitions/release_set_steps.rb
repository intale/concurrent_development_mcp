# frozen_string_literal: true

Given("ReleaseSet {string} has two exact current repository grants for one ChangeSet") do |prefix|
  @release_set_arguments = ReleaseSetScenario.prepare_input(prefix: "cuc-#{prefix.downcase}")
end

When("the agent prepares the ordered ReleaseSet through MCP") do
  @release_set_task_id = call_tool(
    "release_set_prepare",
    @release_set_arguments
  ).dig("result", "taskId")
  assert_acceptance(@release_set_task_id, "release_set_prepare did not return a Task")
  execute_task(@release_set_task_id)
  @release_set_task_state = task_request("tasks/get", @release_set_task_id)
end

Then("the ReleaseSet Task completes with the exact repository order") do
  result = @release_set_task_state.dig("result", "result")
  content = result.fetch("structuredContent")
  assert_acceptance_equal("completed", @release_set_task_state.dig("result", "status"), "Task")
  assert_acceptance_equal(false, result.fetch("isError"), "ReleaseSet error")
  assert_acceptance_equal("ok", content.fetch("status"), "ReleaseSet result")
  assert_acceptance_equal(
    %w[billing ledger],
    content.dig("data", "ordered_members").map { _1.fetch("repository_id") },
    "Repository order"
  )
end

Then("one prepared fact and command completion preserve the Task trace") do
  prepared = release_set_events(@release_set_arguments.fetch(:release_set_id)).sole
  completion = command_events(@release_set_arguments.fetch(:command_id)).sole
  started = task_events(@release_set_task_id).find do |event|
    event.type == "CoordinationTaskExecutionStarted"
  end
  assert_acceptance(started, "ReleaseSet Task has no execution-started fact")
  assert_acceptance_equal(started.id, prepared.causation_id, "Preparation causation")
  assert_acceptance_equal(started.id, completion.causation_id, "Completion causation")
  assert_acceptance_equal(
    [ started.correlation_id ],
    [ prepared, completion ].map(&:correlation_id).uniq,
    "Preparation correlation"
  )
end

Then("the ReleaseSet remains available as not observed before projection") do
  content = release_set_view(@release_set_arguments.fetch(:release_set_id))
  assert_acceptance_equal("not_found", content.fetch("status"), "Lagging ReleaseSet")
  assert_acceptance(
    (content.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "Lagging ReleaseSet must not expose a freshness gate"
  )
end

When("the ReleaseSet preparation reaches the read side twice") do
  event = release_set_events(@release_set_arguments.fetch(:release_set_id)).sole
  2.times { Coordinator::Container["projectors.release_sets_v1"].call(event) }
end

Then("the ordered ReleaseSet is available without a freshness gate") do
  content = release_set_view(@release_set_arguments.fetch(:release_set_id))
  release_set = content.dig("data", "release_set")
  assert_acceptance_equal("ok", content.fetch("status"), "ReleaseSet view")
  assert_acceptance_equal(
    %w[billing ledger],
    release_set.fetch("ordered_members").map { _1.fetch("repository_id") },
    "Projected repository order"
  )
  assert_acceptance_equal("prepared", release_set.fetch("status"), "Projected status")
  assert_acceptance(
    (release_set.keys & %w[fresh pending projection_status stream_revision]).empty?,
    "ReleaseSet view must not expose a freshness gate"
  )
end

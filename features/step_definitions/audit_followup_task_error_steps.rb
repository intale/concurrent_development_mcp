# frozen_string_literal: true

Given("the production subscription sets are running") do
  start_live_subscriptions
end

Given("no {word} with identifier {word} exists") do |target, identifier|
  @audit_missing_target = { target:, identifier: }
end

When("agent {string} submits the {word} command through public MCP") do |agent_id, tool_name|
  tools = mcp_request(method: "tools/list", params: {}).dig("result", "tools")
  tool = tools.find { _1.fetch("name") == tool_name }
  raise "Tool #{tool_name} was not discovered" unless tool

  response = call_tool(
    tool_name,
    audit_missing_target_arguments(tool_name:, agent_id:)
  )
  @audit_task_id = response.dig("result", "taskId")
  raise "#{tool_name} did not return a Task" unless @audit_task_id

  @audit_tool_name = tool_name
  @audit_tool_output_schema = tool.fetch("outputSchema")
end

Then("the returned MCP Task eventually completes with isError true") do
  @audit_terminal_task = await_task_terminal(@audit_task_id)
  result = @audit_terminal_task.dig("result", "result")
  expected_code = {
    "operation_batch_cancel" => "operation_batch_not_found",
    "release_verification_record" => "release_set_not_found"
  }.fetch(@audit_tool_name)

  assert_acceptance_equal("completed", @audit_terminal_task.dig("result", "status"), "Task status")
  assert_acceptance_equal(true, result.fetch("isError"), "Task isError")
  assert_acceptance_equal(
    expected_code,
    result.dig("structuredContent", "data", "code"),
    "Task denial code"
  )
end

Then("its error is valid for the originating {word} output schema") do |tool_name|
  assert_acceptance_equal(@audit_tool_name, tool_name, "originating tool")
  structured_content = @audit_terminal_task.dig("result", "result", "structuredContent")
  ::MCP::Tool::OutputSchema.new(@audit_tool_output_schema).validate_result(structured_content)
end

Then("redelivery leaves one terminal Task outcome") do
  original = @audit_terminal_task.dig("result", "result")
  restart_process_subscriptions
  redelivered = await_task_terminal(@audit_task_id).dig("result", "result")

  assert_acceptance_equal(original, redelivered, "redelivered terminal Task result")
end

Given("agent {string} owns an active Attempt for WorkItem {string}") do |agent_id, work_item_id|
  @audit_context_coordination = audit_prepare_context_work_item(
    work_item_id:,
    owner_id: agent_id,
    attempt_id: "A-#{work_item_id.delete_prefix('W-')}-001"
  )
end

When("agent {string} abandons that Attempt through public MCP") do |agent_id|
  assert_acceptance_equal(
    @audit_context_coordination.fetch(:owner_id),
    agent_id,
    "Attempt owner attribution"
  )
  @audit_abandonment = audit_abandon_attempt(@audit_context_coordination)
end

Then("the abandonment Task completes successfully") do
  assert_acceptance_equal(
    @audit_context_coordination.fetch(:attempt_id),
    @audit_abandonment.dig(:content, "data", "attempt_id"),
    "Abandoned Attempt receipt"
  )
end

Then("the latest available WorkItem context eventually reports it ready") do
  @audit_ready_context = audit_await_work_item_context(
    work_item_id: @audit_context_coordination.fetch(:work_item_id),
    status: "ready",
    active_attempt_id: nil
  )
end

Then("the abandoned Attempt remains attributed in its history") do
  coordination = @audit_context_coordination
  @audit_attempt_history = await_read_model("abandoned Attempt history to become available") do
    content = audit_attempt_list(work_item_id: coordination.fetch(:work_item_id), limit: 100)
    attempt = content.dig("data", "page", "items")&.find do |item|
      item.fetch("attempt_id") == coordination.fetch(:attempt_id)
    end
    matches = attempt&.fetch("status") == "abandoned" &&
              attempt.fetch("agent_id") == coordination.fetch(:owner_id) &&
              attempt.fetch("abandonment_reason") == audit_abandonment_reason
    [ matches, content ]
  end
end

Given("agent {string} abandoned its active Attempt for WorkItem {string}") do |agent_id, work_item_id|
  @audit_context_coordination = audit_prepare_context_work_item(
    work_item_id:,
    owner_id: agent_id,
    attempt_id: "A-#{work_item_id.delete_prefix('W-')}-001"
  )
  @audit_abandonment = audit_abandon_attempt(@audit_context_coordination)
  audit_await_work_item_context(work_item_id:, status: "ready", active_attempt_id: nil)
end

When("independent agent {string} reconstructs context and acquires the WorkItem") do |agent_id|
  coordination = @audit_context_coordination
  observed = call_tool(
    "coord_context",
    { work_item_id: coordination.fetch(:work_item_id) },
    client_id: agent_id
  ).dig("result", "structuredContent")
  work_item = observed.dig("data", "context", "work_items")&.find do |item|
    item.fetch("work_item_id") == coordination.fetch(:work_item_id)
  end
  assert_acceptance_equal("ready", work_item&.fetch("status"), "Reconstructed WorkItem status")

  @audit_replacement_attempt_id = "A-#{coordination.fetch(:work_item_id).delete_prefix('W-')}-002"
  @audit_reacquisition = audit_submit_success(
    "work_item_acquire",
    {
      command_id: "cmd-aud2-reacquire-#{coordination.fetch(:work_item_id)}",
      actor: { kind: "agent", id: agent_id },
      change_set_id: coordination.fetch(:change_set_id),
      work_item_id: coordination.fetch(:work_item_id),
      attempt_id: @audit_replacement_attempt_id,
      base_snapshots: [
        { repository_id: coordination.fetch(:repository_id), commit_oid: "b" * 40 }
      ]
    },
    client_id: agent_id
  )
  @audit_context_coordination = coordination.merge(
    owner_id: agent_id,
    attempt_id: @audit_replacement_attempt_id
  )
end

Then("agent {string} receives a new authorized Attempt") do |agent_id|
  assert_acceptance_equal(agent_id, @audit_context_coordination.fetch(:owner_id), "Replacement owner")
  assert_acceptance_equal(
    @audit_replacement_attempt_id,
    @audit_reacquisition.dig(:content, "data", "attempt_id"),
    "Replacement Attempt receipt"
  )
end

Then("the context identifies only that Attempt as active") do
  coordination = @audit_context_coordination
  payload = audit_await_work_item_context(
    work_item_id: coordination.fetch(:work_item_id),
    status: "acquired",
    active_attempt_id: coordination.fetch(:attempt_id),
    client_id: coordination.fetch(:owner_id),
    attempt_status: "started"
  )
  work_items = payload.dig("data", "context", "work_items")
  active = work_items.select { _1.fetch("active_attempt_id") }

  assert_acceptance_equal(1, active.length, "Active WorkItems")
  assert_acceptance_equal(coordination.fetch(:attempt_id), active.sole.fetch("active_attempt_id"), "Active Attempt")
  assert_acceptance_equal(coordination.fetch(:owner_id), active.sole.fetch("active_agent_id"), "Active agent")
end

Given("WorkItem {string} has more than 100 completed or abandoned Attempts") do |work_item_id|
  @audit_context_coordination = audit_prepare_context_work_item(
    work_item_id:,
    owner_id: "agent-window",
    attempt_id: "A-AUD2-WINDOW-000"
  )
  @audit_oldest_attempt_id = @audit_context_coordination.fetch(:attempt_id)

  101.times do |offset|
    unless offset.zero?
      attempt_id = format("A-AUD2-WINDOW-%03d", offset)
      audit_submit_success(
        "work_item_acquire",
        {
          command_id: format("cmd-aud2-window-acquire-%03d", offset),
          actor: { kind: "agent", id: "agent-window" },
          change_set_id: @audit_context_coordination.fetch(:change_set_id),
          work_item_id:,
          attempt_id:,
          base_snapshots: [
            {
              repository_id: @audit_context_coordination.fetch(:repository_id),
              commit_oid: "a" * 40
            }
          ]
        },
        client_id: "agent-window"
      )
      @audit_context_coordination = @audit_context_coordination.merge(attempt_id:)
    end

    audit_abandon_attempt(
      @audit_context_coordination,
      command_id: format("cmd-aud2-window-abandon-%03d", offset)
    )
  end
end

When("another agent acquires a fresh Attempt through public MCP") do
  coordination = @audit_context_coordination
  @audit_fresh_attempt_id = "A-AUD2-WINDOW-FRESH"
  @audit_fresh_acquisition = audit_submit_success(
    "work_item_acquire",
    {
      command_id: "cmd-aud2-window-acquire-fresh",
      actor: { kind: "agent", id: "agent-fresh" },
      change_set_id: coordination.fetch(:change_set_id),
      work_item_id: coordination.fetch(:work_item_id),
      attempt_id: @audit_fresh_attempt_id,
      base_snapshots: [
        { repository_id: coordination.fetch(:repository_id), commit_oid: "c" * 40 }
      ]
    },
    client_id: "agent-fresh"
  )
  @audit_context_coordination = coordination.merge(
    owner_id: "agent-fresh",
    attempt_id: @audit_fresh_attempt_id
  )
end

Then("the latest available context eventually includes the fresh Attempt") do
  coordination = @audit_context_coordination
  @audit_window_context = audit_await_work_item_context(
    work_item_id: coordination.fetch(:work_item_id),
    status: "acquired",
    active_attempt_id: @audit_fresh_attempt_id,
    client_id: "agent-fresh",
    attempt_status: "started",
    timeout_seconds: 60
  )
  attempts = @audit_window_context.dig("data", "context", "attempts")
  fresh = attempts.find { _1.fetch("attempt_id") == @audit_fresh_attempt_id }

  assert_acceptance_equal("started", fresh&.fetch("status"), "Fresh Attempt status")
  assert_acceptance_equal("agent-fresh", fresh&.fetch("agent_id"), "Fresh Attempt owner")
end

Then("the recent Attempt window remains bounded") do
  attempts = @audit_window_context.dig("data", "context", "attempts")

  assert_acceptance_equal(100, attempts.length, "Embedded recent Attempt count")
  assert_acceptance_equal(@audit_fresh_attempt_id, attempts.first.fetch("attempt_id"), "Newest Attempt")
  assert_acceptance(
    attempts.none? { _1.fetch("attempt_id") == @audit_oldest_attempt_id },
    "The oldest Attempt must be evicted from embedded context"
  )
end

Then("older Attempt history remains discoverable through bounded pages") do
  work_item_id = @audit_context_coordination.fetch(:work_item_id)
  arguments = { work_item_id:, limit: 40 }
  attempts = []
  page_sizes = []

  loop do
    content = audit_attempt_list(**arguments)
    page = content.dig("data", "page")
    items = page.fetch("items")
    attempts.concat(items)
    page_sizes << items.length
    action = content.fetch("next_actions").find { _1.fetch("tool") == "attempt_list" }
    break unless action

    arguments = action.fetch("arguments").transform_keys(&:to_sym)
  end

  assert_acceptance_equal(102, attempts.length, "Complete Attempt history")
  assert_acceptance(page_sizes.all? { _1 <= 40 }, "Every Attempt page must honor its requested bound")
  assert_acceptance(page_sizes.length >= 3, "Attempt history must require multiple bounded pages")
  oldest = attempts.find { _1.fetch("attempt_id") == @audit_oldest_attempt_id }
  assert_acceptance_equal("abandoned", oldest&.fetch("status"), "Oldest Attempt status")
end

def audit_missing_target_arguments(tool_name:, agent_id:)
  command_id = "cmd-aud2-denial-#{tool_name.tr('_', '-')}"
  actor = { kind: "agent", id: agent_id }
  identifier = @audit_missing_target.fetch(:identifier)

  return { command_id:, actor:, batch_id: identifier } if tool_name == "operation_batch_cancel"

  {
    command_id:,
    actor:,
    release_set_id: identifier,
    integration_events: [ 1, 2 ].map do |revision|
      {
        event_id: format("0198e03a-d112-7000-8000-%012d", 110 + revision),
        type: "RepositoryIntegrationRecorded",
        stream_context: "DevelopmentIntegration",
        stream_name: "ReleaseSet",
        stream_id: identifier,
        stream_revision: revision
      }
    end,
    evidence: {
      producer: { name: "audit-agent", version: "1" },
      run_id: "run-aud2-missing-release-set",
      environment_digest: "sha256:#{'a' * 64}",
      result_digest: "sha256:#{'b' * 64}",
      outcome: "passed",
      findings: [],
      produced_at: "2026-08-27T14:00:00.000000Z"
    }
  }
end

def audit_prepare_context_work_item(work_item_id:, owner_id:, attempt_id:)
  start_live_subscriptions
  prepare_mcp_clients(owner_id)
  suffix = work_item_id.delete_prefix("W-")
  change_set_id = "CS-#{suffix}"
  repository_id = SecureRandom.uuid_v7
  planner = { kind: "agent", id: "audit-planner" }

  audit_submit_success(
    "repository_register",
    {
      command_id: "cmd-aud2-repository-#{suffix}",
      actor: planner,
      repository_id:,
      scope: "project:audit-followup/#{suffix.downcase}",
      repository_key: "audit-followup-#{suffix.downcase}",
      display_name: "Audit follow-up #{suffix}",
      paths: [],
      remotes: []
    }
  )
  audit_submit_success(
    "change_set_create",
    {
      command_id: "cmd-aud2-change-set-#{suffix}",
      actor: planner,
      change_set_id:,
      goal: "Coordinate #{work_item_id} through interruption",
      acceptance_criteria: [ "Abandoned work remains resumable" ]
    }
  )
  audit_submit_success(
    "work_item_create",
    {
      command_id: "cmd-aud2-work-item-#{suffix}",
      actor: planner,
      change_set_id:,
      work_item_id:,
      repository_id:,
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "A replacement agent can continue" ]
    }
  )
  audit_submit_success(
    "change_set_activate",
    {
      command_id: "cmd-aud2-activate-#{suffix}",
      actor: planner,
      change_set_id:
    }
  )
  audit_await_work_item_context(work_item_id:, status: "ready", active_attempt_id: nil)
  audit_submit_success(
    "work_item_acquire",
    {
      command_id: "cmd-aud2-acquire-#{attempt_id}",
      actor: { kind: "agent", id: owner_id },
      change_set_id:,
      work_item_id:,
      attempt_id:,
      base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
    },
    client_id: owner_id
  )
  audit_await_work_item_context(
    work_item_id:,
    status: "acquired",
    active_attempt_id: attempt_id,
    client_id: owner_id,
    attempt_status: "started"
  )

  {
    change_set_id:,
    work_item_id:,
    repository_id:,
    owner_id:,
    attempt_id:
  }
end

def audit_abandon_attempt(coordination, command_id: nil)
  attempt_id = coordination.fetch(:attempt_id)
  audit_submit_success(
    "attempt_abandon",
    {
      command_id: command_id || "cmd-aud2-abandon-#{attempt_id}",
      actor: { kind: "agent", id: coordination.fetch(:owner_id) },
      change_set_id: coordination.fetch(:change_set_id),
      work_item_id: coordination.fetch(:work_item_id),
      attempt_id:,
      reason: audit_abandonment_reason
    },
    client_id: coordination.fetch(:owner_id)
  )
end

def audit_abandonment_reason
  "The agent checkpointed its progress and yielded this WorkItem."
end

def audit_submit_success(tool_name, arguments, client_id: "default")
  response = call_tool(tool_name, arguments, client_id:)
  task_id = response.dig("result", "taskId")
  assert_acceptance(task_id, "#{tool_name} did not return a Task: #{response.inspect}")
  start_process_subscriptions
  terminal = await_task_terminal(task_id, client_id:)
  result = terminal.dig("result", "result")
  content = result&.fetch("structuredContent", nil)

  assert_acceptance_equal("completed", terminal.dig("result", "status"), "#{tool_name} Task status")
  assert_acceptance_equal(false, result&.fetch("isError", nil), "#{tool_name} error flag")
  assert_acceptance_equal("ok", content&.fetch("status", nil), "#{tool_name} outcome")

  { task_id:, terminal:, content: }
end

def audit_await_work_item_context(
  work_item_id:,
  status:,
  active_attempt_id:,
  client_id: "default",
  attempt_status: nil,
  timeout_seconds: LiveSubscriptions::DEFAULT_TIMEOUT_SECONDS
)
  start_read_model_subscriptions
  eventually("WorkItem #{work_item_id} to project as #{status}", timeout_seconds:) do
    content = call_tool(
      "coord_context",
      { work_item_id: },
      client_id:
    ).dig("result", "structuredContent")
    work_item = content.dig("data", "context", "work_items")&.find do |item|
      item.fetch("work_item_id") == work_item_id
    end
    attempt = content.dig("data", "context", "attempts")&.find do |item|
      item.fetch("attempt_id") == active_attempt_id
    end
    matches = work_item&.fetch("status") == status &&
              work_item.fetch("active_attempt_id") == active_attempt_id &&
              (!attempt_status || attempt&.fetch("status") == attempt_status)
    [ matches, content ]
  end
end

def audit_attempt_list(work_item_id:, limit:, after_authorized_global_position: nil)
  arguments = { work_item_id:, limit: }
  if after_authorized_global_position
    arguments[:after_authorized_global_position] = after_authorized_global_position
  end
  call_tool("attempt_list", arguments).dig("result", "structuredContent")
end

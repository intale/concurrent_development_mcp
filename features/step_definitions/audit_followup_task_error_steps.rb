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

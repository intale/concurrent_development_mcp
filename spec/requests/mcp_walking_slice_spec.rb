# frozen_string_literal: true

RSpec.describe "D-053 MCP Tasks walking slice", :event_store, :read_model do
  PROTOCOL_VERSION = "2026-07-28"
  TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "advertises mandatory Tasks and lists only the accepted application tools" do
    discovered = mcp_request(
      id: 1,
      method: "server/discover",
      params: {},
      capable: false
    )

    expect(discovered.dig("result", "supportedVersions")).to include(PROTOCOL_VERSION)
    expect(
      discovered.dig("result", "capabilities", "extensions", TASKS_EXTENSION)
    ).to eq({})

    listed = mcp_request(id: 2, method: "tools/list", params: {})
    tools = listed.dig("result", "tools")
    expect(tools.map { _1.fetch("name") }).to contain_exactly(
      "coord_context",
      "operation_get",
      "change_set_create",
      "work_item_create",
      "work_item_dependency_declare",
      "change_set_activate",
      "work_item_acquire",
      "write_set_reserve",
      "write_set_expand",
      "lease_renew",
      "lease_release"
    )
    expect(tools.find { _1.fetch("name") == "operation_get" }.fetch("annotations")).to include(
      "readOnlyHint" => true,
      "idempotentHint" => true,
      "openWorldHint" => false
    )
    expect(tools.find { _1.fetch("name") == "change_set_create" }.fetch("annotations")).to include(
      "readOnlyHint" => false,
      "idempotentHint" => true,
      "destructiveHint" => false
    )
  end

  it "submits, polls, executes, replays, and independently projects one mutation" do
    arguments = {
      command_id: "cmd-mcp-task-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-MCP-TASK-100",
      goal: "Coordinate repositories",
      acceptance_criteria: [ "Agents do not overlap" ]
    }

    created = call_tool("change_set_create", arguments, id: 1)
    task_id = created.dig("result", "taskId")

    expect(created.fetch("result")).to include(
      "resultType" => "task",
      "status" => "working",
      "taskId" => task_id,
      "ttlMs" => nil,
      "pollIntervalMs" => 500
    )
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])
    expect(command_events(arguments.fetch(:command_id))).to be_empty
    expect(change_set_events(arguments.fetch(:change_set_id))).to be_empty

    working = task_request("tasks/get", task_id:, id: 2)
    expect(working.fetch("result")).to include(
      "resultType" => "complete",
      "status" => "working",
      "taskId" => task_id
    )

    execute_task(task_id)
    completed = task_request("tasks/get", task_id:, id: 3)
    tool_result = completed.dig("result", "result")
    expect(completed.fetch("result")).to include(
      "resultType" => "complete",
      "status" => "completed",
      "taskId" => task_id
    )
    expect(tool_result).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "command_id" => arguments.fetch(:command_id),
        "receipt" => arguments.fetch(:command_id)
      )
    )
    expect(JSON.parse(tool_result.fetch("content").sole.fetch("text"))).to eq(
      tool_result.fetch("structuredContent")
    )

    replay = call_tool("change_set_create", arguments, id: 4)
    replay_task_id = replay.dig("result", "taskId")
    expect(replay_task_id).not_to eq(task_id)
    execute_task(replay_task_id)
    replayed = task_request("tasks/get", task_id: replay_task_id, id: 5)
    expect(replayed.dig("result", "result")).to eq(tool_result)
    expect(command_events(arguments.fetch(:command_id)).length).to eq(1)
    expect(change_set_events(arguments.fetch(:change_set_id)).length).to eq(2)

    absent = call_tool("operation_get", { command_id: arguments.fetch(:command_id) }, id: 6)
    expect(absent.dig("result", "resultType")).to eq("complete")
    expect(absent.dig("result", "structuredContent", "status")).to eq("not_found")

    Coordinator::Read::Projectors::CommandReceiptsV1.new.call(
      command_events(arguments.fetch(:command_id)).sole
    )
    current = call_tool("operation_get", { command_id: arguments.fetch(:command_id) }, id: 7)
    expect(current.dig("result", "structuredContent", "status")).to eq("ok")

    projector = Coordinator::Read::Projectors::CoordContextV1.new
    change_set_events(arguments.fetch(:change_set_id)).each { projector.call(_1) }
    context = call_tool(
      "coord_context",
      { change_set_id: arguments.fetch(:change_set_id) },
      id: 8
    )
    context_payload = context.dig("result", "structuredContent")
    expect(context_payload).to include("status" => "ok")
    expect(context_payload).not_to have_key("projection_status")
    expect(context_payload.dig("data", "context", "change_set", "goal")).to eq(
      "Coordinate repositories"
    )
  end

  it "completes a domain denial as a tool error instead of failing the Task" do
    created = call_tool(
      "work_item_create",
      {
        command_id: "cmd-task-denied",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-missing",
        work_item_id: "W-100",
        repository_id: "billing",
        goal: "Implement billing",
        acceptance_criteria: [ "Verified" ]
      },
      id: 1
    )
    task_id = created.dig("result", "taskId")

    execute_task(task_id)
    denied = task_request("tasks/get", task_id:, id: 2)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result", "isError")).to be(true)
    expect(denied.dig("result", "result", "structuredContent", "status")).to eq("denied")
    expect(denied.dig("result", "result", "structuredContent", "data", "code")).to eq(
      "change_set_not_found"
    )
    expect(command_events("cmd-task-denied")).to be_empty
  end

  it "acknowledges input, cooperatively cancels queued work, and skips execution" do
    created = call_tool(
      "change_set_create",
      {
        command_id: "cmd-task-cancel",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-task-cancel",
        goal: "Cancel before execution",
        acceptance_criteria: [ "No target facts are written" ]
      },
      id: 1
    )
    task_id = created.dig("result", "taskId")

    updated = task_request(
      "tasks/update",
      task_id:,
      id: 2,
      params: { inputResponses: { ignored: { action: "accept" } } }
    )
    cancelled = task_request("tasks/cancel", task_id:, id: 3)
    expect(updated.fetch("result")).to eq("resultType" => "complete")
    expect(cancelled.fetch("result")).to eq("resultType" => "complete")

    state = task_request("tasks/get", task_id:, id: 4)
    expect(state.fetch("result")).to include(
      "status" => "cancelled",
      "statusMessage" => "Cancelled before execution"
    )

    execute_task(task_id)
    expect(command_events("cmd-task-cancel")).to be_empty
    expect(change_set_events("CS-task-cancel")).to be_empty
  end

  it "rejects clients without Tasks and validates Task handles and routing headers" do
    arguments = {
      command_id: "cmd-task-capability",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-task-capability",
      goal: "Require Tasks",
      acceptance_criteria: [ "No synchronous fallback exists" ]
    }
    missing = call_tool(
      "change_set_create",
      arguments,
      id: 1,
      capable: false
    )

    expect(missing.dig("error", "code")).to eq(-32_003)
    expect(missing.dig("error", "data", "requiredCapabilities", "extensions")).to eq(
      TASKS_EXTENSION => {}
    )
    expect(task_events_for_command(arguments.fetch(:command_id))).to be_empty

    query_without_tasks = call_tool(
      "operation_get",
      { command_id: arguments.fetch(:command_id) },
      id: 9,
      capable: false
    )
    expect(query_without_tasks.dig("error", "code")).to eq(-32_003)

    unknown_id = "02919191-9191-7191-8191-919191919191"
    unknown = task_request(
      "tasks/get",
      task_id: unknown_id,
      id: 2,
      expected_status: 400
    )
    expect(unknown.dig("error", "code")).to eq(-32_602)

    task_capability = task_request(
      "tasks/get",
      task_id: unknown_id,
      id: 3,
      capable: false
    )
    expect(task_capability.dig("error", "code")).to eq(-32_003)

    missing_name = task_request(
      "tasks/get",
      task_id: unknown_id,
      id: 4,
      include_name: false,
      expected_status: 400
    )
    expect(missing_name.dig("error", "code")).to eq(-32_020)
  end

  it "retains MCP host protection" do
    hostile = ActionDispatch::Integration::Session.new(Rails.application)
    hostile.host! "attacker.example"
    hostile.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id: 1,
        method: "tools/list",
        params: modern_params({})
      ),
      headers: request_headers(method: "tools/list")
    )

    expect(hostile.response.status).to eq(403)
  end

  def call_tool(name, arguments, id:, capable: true)
    mcp_request(
      id:,
      method: "tools/call",
      params: { name:, arguments: },
      capable:,
      name:
    )
  end

  def task_request(
    method,
    task_id:,
    id:,
    params: {},
    capable: true,
    include_name: true,
    expected_status: 200
  )
    mcp_request(
      id:,
      method:,
      params: params.merge(taskId: task_id),
      capable:,
      name: include_name ? task_id : nil,
      expected_status:
    )
  end

  def mcp_request(
    id:,
    method:,
    params:,
    capable: true,
    name: nil,
    envelope: true,
    expected_status: 200
  )
    request_params = envelope ? modern_params(params, capable:) : params
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: request_params),
      headers: request_headers(method:, name:)
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params, capable: true)
    capabilities = capable ? { extensions: { TASKS_EXTENSION => {} } } : {}
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": capabilities,
        "io.modelcontextprotocol/clientInfo": { name: "rspec", version: "1.0" }
      }
    )
  end

  def request_headers(method:, name: nil)
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => PROTOCOL_VERSION,
      "Mcp-Method" => method,
      "Mcp-Name" => name
    }.compact
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def task_events_for_command(command_id)
    PgEventstore.client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 1,
        filter: {
          event_types: [
            {
              type: "CoordinationTaskSubmitted",
              markers: [ "command:#{command_id}" ]
            }
          ]
        }
      }
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end
end

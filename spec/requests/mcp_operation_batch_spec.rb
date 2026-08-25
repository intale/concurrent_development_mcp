# frozen_string_literal: true

RSpec.describe "BAT-01 MCP Operation Batches", :event_store, :read_model do
  BATCH_PROTOCOL_VERSION = "2026-07-28"
  BATCH_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "accepts a Task-backed typed batch, runs its Saga, and serves stale-available projected progress" do
    batch_id = SecureRandom.uuid_v7
    arguments = {
      command_id: "batch-command",
      actor: { kind: "agent", id: "agent-1" },
      batch_id:,
      items: [
        skill_input(command_id: "item-1", expected_revision: 0),
        skill_input(command_id: "item-2", expected_revision: 0)
      ]
    }

    created = call_tool("skill_publish_batch", arguments, id: 1)
    task_id = created.dig("result", "taskId")
    execute_task(task_id)
    completed_task = task_request("tasks/get", task_id, id: 2)
    receipt = completed_task.dig("result", "result", "structuredContent")
    expect(receipt).to include(
      "status" => "ok",
      "data" => include(
        "batch_id" => batch_id,
        "target_tool" => "skill_publish",
        "total" => 2,
        "status" => "accepted"
      )
    )

    absent = call_tool("operation_batch_get", { batch_id: }, id: 3)
    expect(absent.dig("result", "structuredContent", "status")).to eq("not_found")

    created_event = batch_events(batch_id).sole
    Coordinator::Container["process_managers.operation_batch_runner"].call(created_event)
    batch_events(batch_id).each do |event|
      Coordinator::Container["projectors.operation_batches_v1"].call(event)
    end

    available = call_tool("operation_batch_get", { batch_id:, limit: 100 }, id: 4)
      .dig("result", "structuredContent")
    expect(available).to include(
      "status" => "ok",
      "data" => include(
        "batch" => include(
          "batch_id" => batch_id,
          "status" => "completed_with_errors",
          "succeeded" => 1,
          "rejected" => 1,
          "not_run" => 0
        )
      )
    )
    expect(available.dig("data", "batch", "outcomes").map { _1.fetch("status") }).to eq(
      %w[succeeded rejected]
    )
  end

  it "rejects malformed nested items before allocating a Task" do
    response = call_tool(
      "skill_publish_batch",
      {
        command_id: "invalid-batch-command",
        actor: { kind: "agent", id: "agent-1" },
        batch_id: SecureRandom.uuid_v7,
        items: [ skill_input(command_id: "item-1", name: " bad ") ]
      },
      id: 1,
      expected_status: 400
    )

    expect(response.dig("error", "data", "code")).to eq("invalid_input")
    expect(task_events_for_command("invalid-batch-command")).to be_empty
  end

  def skill_input(**overrides)
    {
      command_id: "item-1",
      actor: { kind: "agent", id: "agent-1" },
      name: "review",
      scope: "project:alpha",
      expected_revision: 0,
      description: "Review a change",
      instructions: "Inspect the complete diff.",
      assets: []
    }.merge(overrides)
  end

  def call_tool(name, arguments, id:, expected_status: 200)
    mcp_request(id:, method: "tools/call", name:, params: { name:, arguments: }, expected_status:)
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id }, expected_status: 200)
  end

  def mcp_request(id:, method:, params:, name:, expected_status:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => BATCH_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => BATCH_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { BATCH_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
  end

  def task_events(task_id)
    event_store.read(streams.coordination_task(task_id), Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY)
  end

  def task_events_for_command(command_id)
    PgEventstore.client.read(
      PgEventstore::Stream.all_stream,
      options: {
        direction: :asc,
        max_count: 1,
        filter: {
          event_types: [
            { type: "CoordinationTaskSubmitted", markers: [ "command:#{command_id}" ] }
          ]
        }
      }
    )
  end

  def batch_events(batch_id)
    event_store.read(streams.operation_batch(batch_id), Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY)
  end
end

# frozen_string_literal: true

RSpec.describe "D-045 MCP walking slice", :event_store, :read_model do
  let(:event_store) { Coordinator::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "initializes and discovers only the seven accepted tools with stable annotations" do
    initialized = mcp_request(
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-11-25",
        capabilities: {},
        clientInfo: { name: "rspec", version: "1.0" }
      },
      protocol_header: false
    )
    expect(initialized.dig("result", "protocolVersion")).to eq("2025-11-25")

    listed = mcp_request(id: 2, method: "tools/list", params: {})
    tools = listed.dig("result", "tools")
    expect(tools.map { _1.fetch("name") }).to contain_exactly(
      "coord_context",
      "operation_get",
      "change_set_create",
      "work_item_create",
      "work_item_dependency_declare",
      "change_set_activate",
      "work_item_acquire"
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

  it "commits, replays, recovers by operation, and returns barrier-confirmed context" do
    arguments = {
      command_id: "cmd-mcp-100",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-MCP-100",
      goal: "Coordinate repositories",
      acceptance_criteria: [ "Agents do not overlap" ]
    }

    accepted = call_tool("change_set_create", arguments, id: 1)
    replayed = call_tool("change_set_create", arguments, id: 2)
    accepted_payload = accepted.dig("result", "structuredContent")
    replayed_payload = replayed.dig("result", "structuredContent")

    expect(accepted.dig("result", "isError")).to be(false)
    expect(accepted_payload).to include(
      "status" => "ok",
      "command_id" => "cmd-mcp-100",
      "receipt" => "cmd-mcp-100",
      "projection_status" => "pending"
    )
    expect(JSON.parse(accepted.dig("result", "content").sole.fetch("text"))).to eq(accepted_payload)
    expect(replayed_payload).to eq(accepted_payload)
    expect(command_events("cmd-mcp-100").length).to eq(1)
    expect(change_set_events("CS-MCP-100").length).to eq(2)

    pending = call_tool("operation_get", { command_id: "cmd-mcp-100" }, id: 3)
    expect(pending.dig("result", "structuredContent", "status")).to eq("pending_projection")

    projector = Coordinator::Projectors::CoordContextV1.new
    change_set_events("CS-MCP-100").each { projector.call(_1) }
    current_operation = call_tool("operation_get", { command_id: "cmd-mcp-100" }, id: 4)
    expect(current_operation.dig("result", "structuredContent", "status")).to eq("ok")

    context = call_tool(
      "coord_context",
      { change_set_id: "CS-MCP-100", after_command_id: "cmd-mcp-100" },
      id: 5
    )
    context_payload = context.dig("result", "structuredContent")
    expect(context_payload).to include(
      "status" => "ok",
      "projection_status" => "current_for_requested_command"
    )
    expect(context_payload.dig("data", "context", "change_set", "goal")).to eq("Coordinate repositories")
  end

  it "returns a normal structured result for a domain denial" do
    denied = call_tool(
      "work_item_create",
      {
        command_id: "cmd-denied",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-missing",
        work_item_id: "W-100",
        repository_id: "billing",
        goal: "Implement billing",
        acceptance_criteria: [ "Verified" ]
      },
      id: 1
    )

    expect(denied.dig("result", "isError")).to be(false)
    expect(denied.dig("result", "structuredContent", "status")).to eq("denied")
    expect(denied.dig("result", "structuredContent", "data", "code")).to eq("change_set_not_found")
    expect(command_events("cmd-denied")).to be_empty
  end

  it "retains MCP host protection" do
    hostile = ActionDispatch::Integration::Session.new(Rails.application)
    hostile.host! "attacker.example"
    hostile.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list", params: {}),
      headers: request_headers
    )

    expect(hostile.response.status).to eq(403)
  end

  def call_tool(name, arguments, id:)
    mcp_request(
      id:,
      method: "tools/call",
      params: { name:, arguments: }
    )
  end

  def mcp_request(id:, method:, params:, protocol_header: true)
    headers = request_headers
    headers.delete("MCP-Protocol-Version") unless protocol_header
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params:),
      headers:
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
  end

  def request_headers
    {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "MCP-Protocol-Version" => "2025-11-25"
    }
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::EventQueries::COMMAND_COMPLETION)
  end

  def change_set_events(change_set_id)
    event_store.read(streams.change_set(change_set_id), Coordinator::EventQueries::CHANGE_SET_FOR_ACTIVATION)
  end
end

# frozen_string_literal: true

RSpec.describe "GDN-01 MCP guidance evidence" do
  GUIDANCE_PROTOCOL_VERSION = "2026-07-28"
  GUIDANCE_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:arguments) do
    {
      command_id: "cmd-mcp-guidance-1",
      actor: { kind: "agent", id: "host-1" },
      message_id: "M-mcp-guidance-1",
      conversation_id: "C-mcp-guidance-1",
      source: "mcp_client",
      text: "Do not use Redis in billing.",
      anchors: {
        repository_ids: [ "018f0f4d-4e45-7abc-8def-000000000711" ],
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: nil
      }
    }
  end

  it "records evidence through a durable Task", :event_store do
    created = call_tool("guidance_record", arguments, id: 2)
    task_id = created.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])

    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 3)
    result = completed.dig("result", "result", "structuredContent")
    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false)
    expect(result).to include(
      "status" => "ok",
      "data" => include(
        "message_id" => arguments.fetch(:message_id),
        "source" => "mcp_client",
        "policy_status" => "evidence_only"
      )
    )

    submitted, started, task_completed = task_events(task_id)
    utterance = conversation_events(arguments.fetch(:conversation_id)).sole
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    expect(utterance.type).to eq("UserUtteranceRecorded")
    expect(utterance.causation_id).to eq(started.id)
    command_facts = CommandTraceFixture.domain_events(task_id, event_store:)
    expect(command_facts.map(&:causation_id).uniq).to eq([ started.id ])
    expect(command_terminal.causation_id).to eq(command_facts.last.id)
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect(
      ([ submitted, started, utterance, command_terminal, task_completed ]).map(&:correlation_id).uniq
    ).to eq([ submitted.correlation_id ])
    expect([ utterance, command_terminal ]).to all(
      satisfy { !_1.metadata.key?("causation_id") && !_1.metadata.key?("correlation_id") }
    )
  end

  it "serves a directly persisted available guidance projection", :read_model do
    create(
      :coordinator_read_user_utterance,
      message_id: arguments.fetch(:message_id),
      conversation_id: arguments.fetch(:conversation_id),
      text: arguments.fetch(:text),
      source: arguments.fetch(:source),
      anchors: arguments.fetch(:anchors).transform_keys(&:to_s),
      actor_kind: "agent",
      actor_id: "host-1"
    )

    available = guidance_get(arguments.fetch(:message_id), id: 4)
    expect(available).to include("status" => "ok")
    expect(available.fetch("data").fetch("guidance")).to include(
      "message_id" => arguments.fetch(:message_id),
      "text" => arguments.fetch(:text),
      "source" => "mcp_client",
      "policy_status" => "evidence_only",
      "actor" => {
        "kind" => "agent",
        "id" => "host-1",
        "authenticated" => false
      }
    )
    expect(available.keys & %w[active fresh pending projection_status]).to be_empty
  end

  it "keeps forwarded evidence distinct and denies reuse of its global message identity", :event_store do
    forwarded = arguments.merge(
      command_id: "cmd-mcp-guidance-forwarded",
      message_id: "M-mcp-guidance-forwarded",
      conversation_id: "C-mcp-guidance-forwarded",
      source: "agent_forwarded"
    )
    first_task = call_tool("guidance_record", forwarded, id: 1).dig("result", "taskId")
    execute_task(first_task)

    expect(conversation_events(forwarded.fetch(:conversation_id)).sole.type).to eq(
      "UserUtteranceForwardedByAgent"
    )

    duplicate = forwarded.merge(
      command_id: "cmd-mcp-guidance-duplicate",
      conversation_id: "C-mcp-guidance-other",
      source: "mcp_client"
    )
    duplicate_task = call_tool("guidance_record", duplicate, id: 2).dig("result", "taskId")
    execute_task(duplicate_task)
    denied = task_request("tasks/get", duplicate_task, id: 3)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result", "isError")).to be(true)
    expect(
      denied.dig("result", "result", "structuredContent", "data", "code")
    ).to eq("message_already_recorded")
    expect(conversation_events("C-mcp-guidance-other")).to be_empty
    expect(CommandTraceFixture.events(duplicate_task, event_store:).map(&:type)).to eq(
      [ "CommandRegistered", "CommandRejected" ]
    )
  end

  def call_tool(name, tool_arguments, id:)
    mcp_request(
      id:,
      method: "tools/call",
      name:,
      params: { name:, arguments: tool_arguments }
    )
  end

  def guidance_get(message_id, id:)
    call_tool("guidance_get", { message_id: }, id:).dig("result", "structuredContent")
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, params:, name:)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id:,
        method:,
        params: modern_params(params)
      ),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => GUIDANCE_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => GUIDANCE_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { GUIDANCE_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    CommandResultFixture.project(task_id, event_store:)
  end

  def task_events(task_id)
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def conversation_events(conversation_id)
    event_store.read(
      streams.conversation(conversation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end
end

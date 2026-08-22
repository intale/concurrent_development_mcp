# frozen_string_literal: true

RSpec.describe "GDN-02 MCP interpretation proposals", :event_store, :read_model do
  INTERPRETATION_PROTOCOL_VERSION = "2026-07-28"
  INTERPRETATION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:arguments) do
    InterpretationInput.build(
      command_id: "cmd-mcp-interpretation",
      interpretation_id: "I-mcp-interpretation",
      source_message_id: "M-mcp-interpretation",
      effect: "forbid",
      modality: "must_not",
      enforcement: InterpretationInput.advisory_enforcement.merge(
        level: "merge_gate",
        on_violation: "block"
      )
    )
  end

  before do
    Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
      command_id: "cmd-mcp-interpretation-source",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-mcp-interpretation",
      conversation_id: "C-mcp-interpretation",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: nil
      }
    ).value!
  end

  it "records an atomic source-bound proposal Task and serves its available projection" do
    expect(interpretation_list(id: 1)).to include("status" => "not_found")

    created = call_tool("decision_interpretation_propose", arguments, id: 2)
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
        "interpretation_id" => "I-mcp-interpretation",
        "source_message_id" => "M-mcp-interpretation",
        "assessment" => include("status" => "confirmation_required")
      )
    )

    submitted, started, task_completed = task_events(task_id)
    proposal, clarification = interpretation_events
    completion = command_events(arguments.fetch(:command_id)).sole
    source = guidance_events.sole
    expect([ proposal, clarification ].map(&:type)).to eq(%w[
      DecisionInterpretationProposed
      DecisionClarificationRequired
    ])
    expect([ proposal, clarification ].map(&:stream_revision)).to eq([ 0, 1 ])
    expect([ proposal, clarification, completion ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(completion.id)
    expect(
      [ submitted, started, proposal, clarification, completion, task_completed ]
        .map(&:correlation_id).uniq
    ).to eq([ submitted.correlation_id ])
    expect(proposal.correlation_id).not_to eq(source.correlation_id)
    expect(proposal.data.fetch("source_event")).to include(
      "event_id" => source.id,
      "type" => source.type,
      "stream_revision" => source.stream_revision
    )
    expect([ proposal, clarification, completion ]).to all(
      satisfy { !_1.metadata.key?("causation_id") && !_1.metadata.key?("correlation_id") }
    )

    expect(interpretation_list(id: 4)).to include("status" => "not_found")
    projector = Coordinator::Container["projectors.decision_interpretations_v1"]
    interpretation_events.each { projector.call(_1) }

    available = interpretation_list(id: 5)
    expect(available).to include("status" => "ok")
    expect(available.dig("data", "page")).to include(
      "message_id" => "M-mcp-interpretation",
      "next_after_revision" => nil
    )
    expect(available.dig("data", "page", "interpretations").sole).to include(
      "interpretation_id" => "I-mcp-interpretation",
      "policy_status" => "proposal_only",
      "assessment" => include("status" => "confirmation_required"),
      "clarification_event" => include("event_id" => clarification.id)
    )
    expect(available.keys & %w[active fresh pending projection_status]).to be_empty

    duplicate_arguments = arguments.merge(command_id: "cmd-mcp-interpretation-duplicate")
    duplicate_task = call_tool(
      "decision_interpretation_propose",
      duplicate_arguments,
      id: 6
    ).dig("result", "taskId")
    execute_task(duplicate_task)
    duplicate = task_request("tasks/get", duplicate_task, id: 7)
    expect(duplicate.dig("result", "status")).to eq("completed")
    expect(duplicate.dig("result", "result", "isError")).to be(true)
    expect(duplicate.dig("result", "result", "structuredContent", "data", "code")).to eq(
      "interpretation_already_proposed"
    )
    expect(interpretation_events.length).to eq(2)
  end

  def call_tool(name, tool_arguments, id:)
    mcp_request(
      id:,
      method: "tools/call",
      name:,
      params: { name:, arguments: tool_arguments }
    )
  end

  def interpretation_list(id:)
    call_tool(
      "decision_interpretation_list",
      { message_id: "M-mcp-interpretation", after_revision: -1, limit: 20 },
      id:
    ).dig("result", "structuredContent")
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
        "MCP-Protocol-Version" => INTERPRETATION_PROTOCOL_VERSION,
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
        "io.modelcontextprotocol/protocolVersion" => INTERPRETATION_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { INTERPRETATION_TASKS_EXTENSION => {} }
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
    event_store.read(
      streams.coordination_task(task_id),
      Coordinator::Write::EventQueries::COORDINATION_TASK_HISTORY
    )
  end

  def guidance_events
    event_store.read(
      streams.conversation("C-mcp-interpretation"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def interpretation_events
    event_store.read(
      streams.interpretation("M-mcp-interpretation"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionInterpretationProposed DecisionClarificationRequired],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end
end

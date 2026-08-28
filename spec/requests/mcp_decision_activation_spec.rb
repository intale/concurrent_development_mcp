# frozen_string_literal: true

RSpec.describe "DEC-01 MCP Decision activation", :event_store, :read_model do
  DECISION_PROTOCOL_VERSION = "2026-07-28"
  DECISION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:arguments) do
    InterpretationInput.activation(
      command_id: "cmd-mcp-decision-activation",
      decision_id: "D-mcp-decision",
      interpretation_id: "I-mcp-decision"
    )
  end

  before { seed_accepted_interpretation }

  it "activates only through a traced Task and serves every available projection stage" do
    expect(decision_events).to be_empty
    expect(decision_get(id: 1)).to include("status" => "not_found")

    created = call_tool("decision_activate", arguments, id: 2)
    task_id = created.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])
    expect(decision_events).to be_empty

    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 3)
    result = completed.dig("result", "result", "structuredContent")
    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false)
    expect(result).to include(
      "status" => "ok",
      "data" => include(
        "decision_id" => "D-mcp-decision",
        "interpretation_id" => "I-mcp-decision",
        "outcome" => "activated",
        "policy_status" => "active",
        "partitions" => [
          include(
            "partition" => include("partition_id" => "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing"),
            "partition_revision" => 0
          )
        ]
      ),
      "next_actions" => [
        include("tool" => "decision_get", "arguments" => { "decision_id" => "D-mcp-decision" })
      ]
    )

    submitted, started, task_completed = task_events(task_id)
    recorded, activated = decision_events
    slot = result.dig("data", "slot")
    slot_facts = slot_events(slot.fetch("slot_id"))
    partition = partition_events.sole
    completion = command_events(arguments.fetch(:command_id)).sole
    domain_facts = [ recorded, activated, *slot_facts, partition ]

    expect(domain_facts.map(&:type)).to eq(%w[
      DecisionRecorded
      DecisionActivated
      DecisionSlotOpened
      DecisionSlotHeadChanged
      DecisionPartitionAdvanced
    ])
    expect([ *domain_facts, completion ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(completion.id)
    expect([ submitted, started, *domain_facts, completion, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
    expect([ *domain_facts, completion ]).to all(
      satisfy { !_1.metadata.key?("causation_id") && !_1.metadata.key?("correlation_id") }
    )

    expect(decision_get(id: 4)).to include("status" => "not_found")
    projector.call(recorded)
    recorded_view = decision_get(id: 5)
    expect(recorded_view).to include(
      "status" => "ok",
      "data" => include(
        "decision" => include(
          "decision_id" => "D-mcp-decision",
          "policy_status" => "recorded",
          "activated" => nil
        )
      )
    )
    expect(recorded_view.keys & %w[active fresh pending projection_status stream_revision]).to be_empty

    [ activated, *slot_facts, partition ].each do |event|
      projector.call(event)
      projector.call(event)
    end
    active_view = decision_get(id: 6)
    expect(active_view).to include(
      "status" => "ok",
      "data" => include(
        "decision" => include(
          "decision_id" => "D-mcp-decision",
          "policy_status" => "active",
          "slot" => include("slot_id" => slot.fetch("slot_id")),
          "partitions" => [ include("partition_id" => "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing") ],
          "activated" => include("event" => include("event_id" => activated.id))
        )
      )
    )
  end

  it "returns command denials through Tasks and rejects malformed input before Task allocation" do
    missing = arguments.merge(
      command_id: "cmd-mcp-decision-missing",
      decision_id: "D-missing",
      interpretation_id: "I-missing"
    )
    task_id = call_tool("decision_activate", missing, id: 1).dig("result", "taskId")
    execute_task(task_id)
    denied = task_request("tasks/get", task_id, id: 2)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "denied",
        "data" => include("code" => "interpretation_not_accepted")
      )
    )
    expect(command_events(missing.fetch(:command_id))).to be_empty
    expect(decision_events("D-missing")).to be_empty

    malformed = arguments.merge(command_id: "cmd-mcp-decision-malformed", unexpected: true)
    response = call_tool("decision_activate", malformed, id: 3)

    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content").sole.fetch("text")).to include(
      "unexpected",
      "disallowed additional property"
    )
    expect(task_events_for_command(malformed.fetch(:command_id))).to be_empty
  end

  def seed_accepted_interpretation
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-mcp-decision-guidance",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-mcp-decision",
      conversation_id: "C-mcp-decision",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, InterpretationInput.build(
      command_id: "cmd-mcp-decision-proposal",
      interpretation_id: "I-mcp-decision",
      source_message_id: "M-mcp-decision"
    ))
    execute(Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, InterpretationInput.adjudication(
      command_id: "cmd-mcp-decision-adjudication",
      source_message_id: "M-mcp-decision",
      interpretation_id: "I-mcp-decision"
    ))
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def call_tool(name, tool_arguments, id:, expected_status: 200)
    mcp_request(
      id:,
      method: "tools/call",
      name:,
      params: { name:, arguments: tool_arguments },
      expected_status:
    )
  end

  def decision_get(id:)
    call_tool("decision_get", { decision_id: "D-mcp-decision" }, id:)
      .dig("result", "structuredContent")
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, params:, name:, expected_status: 200)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => DECISION_PROTOCOL_VERSION,
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
        "io.modelcontextprotocol/protocolVersion" => DECISION_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { DECISION_TASKS_EXTENSION => {} }
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

  def decision_events(decision_id = "D-mcp-decision")
    event_store.read(streams.decision(decision_id), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
  end

  def slot_events(slot_id)
    event_store.read(
      streams.decision_slot(slot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def partition_events
    event_store.read(
      streams.decision_partition("repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def projector
    Coordinator::Container["projectors.decision_governance_v1"]
  end
end

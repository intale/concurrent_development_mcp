# frozen_string_literal: true

RSpec.describe "CHO-01 MCP Decision resolution", :event_store, :read_model do
  RESOLUTION_PROTOCOL_VERSION = "2026-07-28"
  RESOLUTION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  RESOLUTION_REPOSITORY_ID = RepositoryScenario::DEFAULT_REPOSITORY_ID

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:projector) { Coordinator::Read::Projectors::DecisionGovernanceV1.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:arguments) do
    {
      topic_id: "testing.framework",
      context: {
        repository_id: RESOLUTION_REPOSITORY_ID,
        change_set_id: "CS-mcp-resolve",
        work_item_id: "W-mcp-resolve",
        attempt_id: "A-mcp-resolve",
        phase: "implementation",
        language: "ruby",
        paths: [ "spec/models/order_spec.rb" ],
        agent_role: "implementer"
      }
    }
  end

  before do
    seed_active_decision
    decision_events.each { projector.call(_1) }
    projector.call(partition_events.sole)
  end

  it "exposes latest available context and exact evidence as a read-only MCP tool" do
    response = call_tool("decision_resolve", arguments, id: 1)
    result = response.dig("result", "structuredContent")

    expect(result).to include(
      "status" => "ok",
      "context_token" => a_string_matching(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
      "data" => include(
        "decision_context" => include(
          "digest" => a_string_matching(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
          "document" => include(
            "schema" => "decision-context/v1",
            "resolution_policy" => "testing-framework-resolution/v1",
            "effective_decision" => include(
              "head" => include("decision_id" => "D-mcp-resolve"),
              "value" => include("name" => "rspec"),
              "anchor_kind" => "repository"
            )
          )
        )
      )
    )
    expect(result.fetch("context_token")).to eq(result.dig("data", "decision_context", "digest"))
    expect(result.keys & %w[active fresh pending projection_status stream_revision]).to be_empty
  end

  it "returns a typed result for a registered resolution strategy not implemented by this query" do
    response = call_tool(
      "decision_resolve",
      arguments.merge(topic_id: "testing.required_suites"),
      id: 2
    )

    result = response.dig("result", "structuredContent")
    expect(response.dig("result", "isError")).to be(false)
    expect(result).to include(
      "status" => "invalid",
      "data" => include(
        "code" => "decision_resolution_strategy_not_supported",
        "details" => include(
          "topic_id" => "testing.required_suites",
          "resolution_strategy" => "set_union"
        )
      )
    )
  end

  def seed_active_decision
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-mcp-resolve-guidance",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-mcp-resolve",
      conversation_id: "C-mcp-resolve",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ RESOLUTION_REPOSITORY_ID ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, InterpretationInput.build(
      command_id: "cmd-mcp-resolve-proposal",
      interpretation_id: "I-mcp-resolve",
      source_message_id: "M-mcp-resolve"
    ))
    execute(Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, InterpretationInput.adjudication(
      command_id: "cmd-mcp-resolve-adjudication",
      source_message_id: "M-mcp-resolve",
      interpretation_id: "I-mcp-resolve"
    ))
    execute(Coordinator::Write::Operations::ExecuteActivateDecision, InterpretationInput.activation(
      command_id: "cmd-mcp-resolve-activation",
      decision_id: "D-mcp-resolve",
      interpretation_id: "I-mcp-resolve"
    ))
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def call_tool(name, tool_arguments, id:)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id:,
        method: "tools/call",
        params: modern_params(name:, arguments: tool_arguments)
      ),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => RESOLUTION_PROTOCOL_VERSION,
        "Mcp-Method" => "tools/call",
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => RESOLUTION_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { RESOLUTION_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def decision_events
    event_store.read(streams.decision("D-mcp-resolve"), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
  end

  def partition_events
    event_store.read(
      streams.decision_partition("repo:#{RESOLUTION_REPOSITORY_ID}:testing"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 2,
        direction: :asc
      )
    )
  end
end

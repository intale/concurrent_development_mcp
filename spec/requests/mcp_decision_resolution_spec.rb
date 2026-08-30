# frozen_string_literal: true

RSpec.describe "CHO-01 MCP Decision resolution", :read_model do
  RESOLUTION_PROTOCOL_VERSION = "2026-07-28"
  RESOLUTION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"
  RESOLUTION_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000701"

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
    decision = create(
      :coordinator_read_decision_definition,
      :active,
      decision_id: "D-mcp-resolve",
      repository_id: RESOLUTION_REPOSITORY_ID
    )
    create(
      :coordinator_read_decision_partition_head,
      partition_id: "repo:#{RESOLUTION_REPOSITORY_ID}:testing",
      decision_id: decision.decision_id,
      partition: {
        "partition_id" => "repo:#{RESOLUTION_REPOSITORY_ID}:testing",
        "topic_root" => "testing",
        "anchor_kind" => "repo",
        "anchor_id" => RESOLUTION_REPOSITORY_ID
      },
      decision: decision_head(decision),
      active_decisions: [ decision_head(decision) ]
    )
  end

  it "exposes latest available context and exact evidence as a read-only MCP tool" do
    result = call_tool("decision_resolve", arguments, id: 1).dig("result", "structuredContent")

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

  def decision_head(decision)
    {
      "decision_id" => decision.decision_id,
      "decision_revision" => 1,
      "event" => decision.activated_event
    }
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
end

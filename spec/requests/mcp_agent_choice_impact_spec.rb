# frozen_string_literal: true

RSpec.describe "CHO-02 MCP AgentChoice impact reads", :read_model do
  IMPACT_PROTOCOL_VERSION = "2026-07-28"
  IMPACT_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "serializes independently available Choice and impact projections" do
    choice_id = "CHO-mcp-impact"
    attempt_id = "A-mcp-impact"
    create(:coordinator_read_agent_choice, :accepted, choice_id:)

    expect(choice_view(id: 1)).to include(
      "observation_status" => "accepted",
      "invalidation" => nil
    )
    expect(impact_page(attempt_id:, id: 2)).to include(
      "items" => [],
      "next_global_position" => nil,
      "has_more" => false
    )

    impact = create(:coordinator_read_agent_choice_impact, choice_id:, attempt_id:)
    item = impact_page(attempt_id:, id: 3).fetch("items").sole
    expect(item).to include(
      "choice_id" => choice_id,
      "attempt_id" => attempt_id,
      "outcome" => "invalidated",
      "reason" => "blocking_policy_introduced",
      "source_actor" => include("kind" => "orchestrator", "id" => "guidance-host"),
      "assessment_evidence" => include(
        "event" => include("event_id" => impact.assessment_event.fetch("event_id")),
        "actor" => include("kind" => "system", "id" => "choice-impact")
      )
    )
    expect(choice_view(id: 4)).to include("observation_status" => "accepted", "invalidation" => nil)
  end

  def choice_view(id:)
    call_tool("agent_choice_get", { choice_id: "CHO-mcp-impact" }, id:)
      .dig("result", "structuredContent", "data", "choice")
  end

  def impact_page(attempt_id:, id:)
    call_tool("agent_choice_impact_list", { attempt_id:, limit: 20 }, id:)
      .dig("result", "structuredContent", "data", "page")
  end

  def call_tool(name, arguments, id:)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id:,
        method: "tools/call",
        params: modern_params(name:, arguments:)
      ),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => IMPACT_PROTOCOL_VERSION,
        "Mcp-Method" => "tools/call",
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(name:, arguments:)
    {
      name:,
      arguments:,
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => IMPACT_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { IMPACT_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    }
  end
end

# frozen_string_literal: true

RSpec.describe "IMP-02 MCP verification obligations", :event_store, :read_model do
  OBLIGATION_PROTOCOL_VERSION = "2026-07-28"
  OBLIGATION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "serves an available empty page under lag and then complete projected evidence" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-obligation")
    change_set_id = created.dig(:pair, :ids, :change_set_id)

    lagging = call_tool(
      { change_set_id:, status: "open" },
      id: 1
    ).dig("result", "structuredContent")
    expect(lagging).to include(
      "status" => "ok",
      "data" => include(
        "page" => include("items" => [], "has_more" => false)
      )
    )

    Coordinator::Read::Projectors::VerificationObligationsV1.new.call(created.fetch(:event))
    available = call_tool(
      {
        change_set_id:,
        candidate_id: created.dig(:pair, :target, :candidate_id),
        repository_id: "billing",
        kind: "candidate_compatibility",
        enforcement: "merge_gate",
        status: "open",
        limit: 20
      },
      id: 2
    ).dig("result", "structuredContent")

    item = available.dig("data", "page", "items").sole
    expect(available).to include("status" => "ok")
    expect(item).to include(
      "obligation_id" => created.fetch(:result).obligation_id,
      "kind" => "candidate_compatibility",
      "status" => "open",
      "change_set_id" => change_set_id,
      "enforcement" => "merge_gate",
      "required_evidence" => %w[combined_tests contract_compatibility_review],
      "source_candidate" => include(
        "candidate_id" => created.dig(:pair, :source, :candidate_id)
      ),
      "target_candidate" => include(
        "candidate_id" => created.dig(:pair, :target, :candidate_id)
      ),
      "evidence" => include(
        "global_position" => created.fetch(:event).global_position,
        "causation_id" => created.fetch(:event).causation_id,
        "correlation_id" => created.fetch(:event).correlation_id
      )
    )
  end

  it "rejects an unscoped list request at the MCP schema boundary" do
    response = call_tool({}, id: 1)

    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content", 0, "text")).to start_with("Invalid arguments:")
  end

  private

  def call_tool(arguments, id:, expected_status: 200)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id:,
        method: "tools/call",
        params: modern_params(name: "verification_obligations_list", arguments:)
      ),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => OBLIGATION_PROTOCOL_VERSION,
        "Mcp-Method" => "tools/call",
        "Mcp-Name" => "verification_obligations_list"
      }
    )
    expect(session.response.status).to eq(expected_status), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(name:, arguments:)
    {
      name:,
      arguments:,
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => OBLIGATION_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { OBLIGATION_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    }
  end
end

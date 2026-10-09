# frozen_string_literal: true

RSpec.describe "IMP-02 MCP verification obligations", :read_model do
  OBLIGATION_PROTOCOL_VERSION = "2026-07-28"
  OBLIGATION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "serves an available empty page and then a directly persisted projection" do
    change_set_id = "CS-mcp-obligation"
    lagging = call_tool({ change_set_id:, status: "open" }, id: 1)
      .dig("result", "structuredContent")
    expect(lagging).to include(
      "status" => "ok",
      "data" => include("page" => include("items" => [], "has_more" => false))
    )

    obligation = create(
      :coordinator_read_verification_obligation,
      obligation_id: "OBL-mcp-obligation",
      change_set_id:,
      required_evidence: %w[combined_tests contract_compatibility_review],
      event_global_position: 1_200,
      causation_id: SecureRandom.uuid_v7,
      correlation_id: SecureRandom.uuid_v7
    )
    available = call_tool(
      {
        change_set_id:,
        candidate_id: obligation.target_candidate_id,
        repository_id: obligation.target_repository_id,
        kind: "candidate_compatibility",
        enforcement: "merge_gate",
        status: "open",
        limit: 20
      },
      id: 2
    ).dig("result", "structuredContent")

    item = available.dig("data", "page", "items").sole
    expect(item).to include(
      "obligation_id" => obligation.obligation_id,
      "kind" => "candidate_compatibility",
      "status" => "open",
      "change_set_id" => change_set_id,
      "enforcement" => "merge_gate",
      "required_evidence" => %w[combined_tests contract_compatibility_review],
      "source_candidate" => include("candidate_id" => obligation.source_candidate_id),
      "target_candidate" => include("candidate_id" => obligation.target_candidate_id),
      "evidence" => include(
        "global_position" => 1_200,
        "causation_id" => obligation.causation_id,
        "correlation_id" => obligation.correlation_id
      )
    )
  end

  it "rejects an unscoped list request at the MCP schema boundary" do
    response = call_tool({}, id: 1)

    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content", 0, "text")).to start_with("Invalid arguments:")
  end

  it "exposes the latest available claim and query-time claim state without closing the obligation" do
    claim_causation_id = SecureRandom.uuid_v7
    claim_correlation_id = SecureRandom.uuid_v7
    obligation = create(
      :coordinator_read_verification_obligation,
      :claimed,
      obligation_id: "OBL-mcp-obligation-claim",
      change_set_id: "CS-mcp-obligation-claim",
      claimant_id: "agent-blue",
      claim_claimed_at_domain: Time.utc(2026, 8, 30, 7),
      claim_expires_at_domain: Time.utc(2026, 8, 30, 7, 5),
      claim_event_global_position: 1_301,
      claim_causation_id:,
      claim_correlation_id:
    )

    available = Timecop.freeze(Time.utc(2026, 8, 30, 7, 1)) do
      call_tool(
        {
          obligation_id: obligation.obligation_id,
          claimant_id: "agent-blue",
          claim_state: "active"
        },
        id: 3
      ).dig("result", "structuredContent")
    end

    page = available.dig("data", "page")
    expect(page).to include("observed_at" => "2026-08-30T07:01:00.000000Z")
    expect(page.fetch("items").sole).to include(
      "obligation_id" => obligation.obligation_id,
      "status" => "open",
      "claim_state" => "active",
      "claim" => include(
        "claim_id" => obligation.claim_id,
        "claimant_id" => "agent-blue",
        "fencing_token" => 1,
        "evidence" => include(
          "global_position" => 1_301,
          "causation_id" => claim_causation_id,
          "correlation_id" => claim_correlation_id
        )
      )
    )
  end

  it "filters terminal status and exposes ordered evidence, progress, and outcome provenance" do
    obligation = create(
      :coordinator_read_verification_obligation,
      :claimed,
      :satisfied,
      obligation_id: "OBL-mcp-obligation-evidence",
      change_set_id: "CS-mcp-obligation-evidence",
      required_evidence: [ "combined_tests" ],
      event_global_position: 1_400,
      terminal_causation_id: SecureRandom.uuid_v7,
      terminal_correlation_id: SecureRandom.uuid_v7
    )
    evidence_id = SecureRandom.uuid_v7
    evidence = create(
      :coordinator_read_verification_obligation_evidence_item,
      evidence_id:,
      obligation_id: obligation.obligation_id,
      source_obligation: obligation,
      event_global_position: 1_402,
      causation_id: obligation.terminal_causation_id,
      correlation_id: obligation.terminal_correlation_id
    )

    response = call_tool(
      { obligation_id: obligation.obligation_id, status: "satisfied" },
      id: 4
    )
    expect(response).to include("result" => include("structuredContent" => include("status" => "ok")))
    item = response.fetch("result").fetch("structuredContent").fetch("data").fetch("page").fetch("items").sole
    submitted = item.fetch("submitted_evidence").sole
    expect(item).to include(
      "status" => "satisfied",
      "progress" => {
        "required_evidence_kinds" => [ "combined_tests" ],
        "passed_evidence_kinds" => [ "combined_tests" ],
        "missing_evidence_kinds" => [],
        "evidence_count" => 1
      },
      "outcome" => include(
        "satisfied_at" => "2026-08-30T12:03:00.000000Z",
        "evidence" => include(
          "event" => include("event_id" => obligation.terminal_event.fetch("event_id")),
          "causation_id" => obligation.terminal_causation_id,
          "correlation_id" => obligation.terminal_correlation_id
        )
      )
    )
    expect(submitted).to include(
      "evidence_id" => evidence.evidence_id,
      "evidence_kind" => "combined_tests",
      "assessment" => include("conclusion" => "passed"),
      "evidence" => include(
        "event" => include("event_id" => evidence.event_id),
        "causation_id" => obligation.terminal_causation_id,
        "correlation_id" => obligation.terminal_correlation_id
      )
    )
    expect(item.dig("evidence", "global_position")).to eq(1_400)
    expect(
      call_tool(
        { obligation_id: obligation.obligation_id, status: "open" },
        id: 5
      ).dig("result", "structuredContent", "data", "page", "items")
    ).to be_empty
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

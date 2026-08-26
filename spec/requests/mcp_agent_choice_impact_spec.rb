# frozen_string_literal: true

RSpec.describe "CHO-02 MCP AgentChoice impact reads", :event_store, :read_model do
  IMPACT_PROTOCOL_VERSION = "2026-07-28"
  IMPACT_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:choice_projector) { Coordinator::Read::Projectors::AgentChoicesV1.new }
  let(:impact_projector) { Coordinator::Read::Projectors::AgentChoiceImpactsV1.new }

  it "serves available assessment evidence before the Choice invalidation projection catches up" do
    scenario = impact_scenario
    recorded, accepted, invalidation = scenario.fetch(:choice_events)
    choice_projector.call(recorded)
    choice_projector.call(accepted)

    expect(choice_view(id: 1)).to include(
      "observation_status" => "accepted",
      "invalidation" => nil
    )
    expect(impact_page(id: 2)).to include(
      "items" => [],
      "next_global_position" => nil,
      "has_more" => false
    )

    impact_projector.call(scenario.fetch(:assessment))
    impact = impact_page(id: 3).fetch("items").sole
    expect(impact).to include(
      "choice_id" => scenario.fetch(:choice_id),
      "attempt_id" => scenario.fetch(:attempt_id),
      "outcome" => "invalidated",
      "reason" => "blocking_policy_introduced",
      "source_actor" => include(
        "kind" => "orchestrator",
        "id" => "guidance-host"
      ),
      "assessment_evidence" => include(
        "event" => include("event_id" => scenario.fetch(:assessment).id),
        "actor" => include("kind" => "system", "id" => "agent-choice-decision-impact")
      )
    )
    expect(choice_view(id: 4)).to include("observation_status" => "accepted")

    impact_projector.call(invalidation)
    invalidated = choice_result(id: 5)
    expect(invalidated.dig("data", "choice")).to include(
      "observation_status" => "invalidated",
      "invalidation" => include(
        "assessment_event" => include("event_id" => scenario.fetch(:assessment).id),
        "reason" => "blocking_policy_introduced"
      )
    )
    expect(invalidated.fetch("next_actions")).to contain_exactly(
      include(
        "tool" => "decision_resolve",
        "arguments" => include("topic_id" => "testing.framework")
      )
    )
    expect(invalidated.dig("data", "choice").keys & %w[fresh pending projection_status]).to be_empty
  end

  def impact_scenario
    prefix = "mcp-impact"
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix:)
    decision_id = "D-#{prefix}"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "#{prefix}-base",
      decision_id:,
      option_id: "rspec",
      scope: InterpretationInput.scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ])
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "#{prefix}-change",
      decision_id:,
      option_id: "minitest",
      scope: InterpretationInput.scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ])
    )
    caused_by = AgentChoiceImpactScenario.start_scan(source)
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:, caused_by:)
    assessment = Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(
      event_store: AgentChoiceImpactScenario.event_store
    ).call(invocation).value!
    choice_id = choice.fetch(:identifiers).fetch(:choice_id)
    {
      assessment:,
      attempt_id: choice.fetch(:identifiers).fetch(:attempt_id),
      choice_id:,
      choice_events: AgentChoiceImpactScenario.choice_events(choice_id)
    }
  end

  def choice_view(id:)
    choice_result(id:).dig("data", "choice")
  end

  def choice_result(id:)
    call_tool("agent_choice_get", { choice_id: "CHO-mcp-impact" }, id:)
      .dig("result", "structuredContent")
  end

  def impact_page(id:)
    call_tool(
      "agent_choice_impact_list",
      { attempt_id: "A-mcp-impact", limit: 20 },
      id:
    ).dig("result", "structuredContent", "data", "page")
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

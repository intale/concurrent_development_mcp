# frozen_string_literal: true

RSpec.describe "IMP-01 MCP Candidate impact evidence" do
  CANDIDATE_IMPACT_PROTOCOL_VERSION = "2026-07-28"
  CANDIDATE_IMPACT_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "submits a traced Task with attributed impact evidence", :event_store do
    candidate = CandidateScenario.submit(prefix: "mcp-impact")
    arguments = CandidateScenario.impact_input(candidate)

    created = call_tool("candidate_impact_surface_submit", arguments, id: 1)
    task_id = created.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    execute_task(task_id)

    completed = task_request("tasks/get", task_id, id: 2)
    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "structuredContent")).to include(
      "status" => "ok",
      "data" => include(
        "candidate_id" => "CAN-mcp-impact",
        "evidence_status" => "attributed_unverified"
      )
    )

    submitted, started, task_completed = task_events(task_id)
    assignment = CandidateScenario.candidate_events("CAN-mcp-impact").find do |event|
      event.type == "CandidateImpactSurfaceAssigned"
    end
    surface = event_store.read(
      streams.candidate_impact_surface(assignment.data.fetch("surface_id")),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceDerived" ],
        maximum_count: 1,
        direction: :asc
      )
    ).sole
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    expect(surface.causation_id).to eq(started.id)
    command_facts = CommandTraceFixture.domain_events(task_id, event_store:)
    expect(command_terminal.causation_id).to eq(command_facts.last.id)
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect([ submitted, started, surface, assignment, command_terminal, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
  end

  it "serves a directly persisted attributed surface without a freshness gate", :read_model do
    candidate = create(
      :coordinator_read_candidate,
      :manifest_observed,
      :build_context_observed,
      :impact_surface_observed,
      candidate_id: "CAN-mcp-impact",
      impact_causation_id: SecureRandom.uuid_v7,
      impact_correlation_id: SecureRandom.uuid_v7
    )
    available = call_tool(
      "candidate_impact_get",
      { candidate_id: candidate.candidate_id, direction: "outgoing", limit: 20 },
      id: 3
    ).dig("result", "structuredContent")
    expect(available).to include(
      "status" => "ok",
      "data" => include(
        "page" => include(
          "direction" => "outgoing",
          "impact_surface" => include(
            "evidence_status" => "attributed_unverified",
            "evidence" => include(
              "causation_id" => candidate.impact_causation_id,
              "correlation_id" => candidate.impact_correlation_id
            )
          ),
          "relationships" => [],
          "has_more" => false,
          "next_global_position" => nil
        )
      )
    )
    expect(available.fetch("warnings")).to be_empty
  end

  it "rejects an empty surface before Task allocation", :event_store do
    candidate = CandidateScenario.submit(prefix: "mcp-impact-invalid", build_context: false)
    arguments = CandidateScenario.impact_input(candidate).merge(
      command_id: "cmd-mcp-impact-invalid",
      surface: { produces: [], consumes: [], may_affect: [], assumes: [] }
    )

    response = call_tool(
      "candidate_impact_surface_submit",
      arguments,
      id: 1,
      expected_status: 400
    )

    expect(response.dig("error", "code")).to eq(-32_602)
    expect(response.dig("error", "data", "code")).to eq("invalid_input")
    expect(response.dig("error", "data", "details", "surface")).to include(
      "must contain between 1 and 128 total entries"
    )
    expect(task_events_for_command("cmd-mcp-impact-invalid")).to be_empty
  end

  def call_tool(name, arguments, id:, expected_status: 200)
    mcp_request(id:, method: "tools/call", name:, params: { name:, arguments: }, expected_status:)
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id }, expected_status: 200)
  end

  def mcp_request(id:, method:, params:, name:, expected_status:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => CANDIDATE_IMPACT_PROTOCOL_VERSION,
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
        "io.modelcontextprotocol/protocolVersion" => CANDIDATE_IMPACT_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { CANDIDATE_IMPACT_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    collector = ReportedErrorCollector.new
    Rails.error.subscribe(collector)
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    raise collector.errors.first if collector.errors.any?
    CommandResultFixture.project(task_id, event_store:)
  ensure
    Rails.error.unsubscribe(collector) if collector
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

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end
end

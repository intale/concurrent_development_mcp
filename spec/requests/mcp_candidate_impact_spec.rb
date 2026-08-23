# frozen_string_literal: true

RSpec.describe "IMP-01 MCP Candidate impact evidence", :event_store, :read_model do
  CANDIDATE_IMPACT_PROTOCOL_VERSION = "2026-07-28"
  CANDIDATE_IMPACT_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "submits a traced Task and serves the available attributed surface without a freshness gate" do
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
    candidate_events = CandidateScenario.candidate_events("CAN-mcp-impact")
    surface = candidate_events.find { _1.type == "CandidateImpactSurfaceDerived" }
    completion = command_events(arguments.fetch(:command_id)).sole
    expect(surface.causation_id).to eq(started.id)
    expect(completion.causation_id).to eq(started.id)
    expect(task_completed.causation_id).to eq(completion.id)
    expect([ submitted, started, surface, completion, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )

    absent = call_tool(
      "candidate_impact_get",
      { candidate_id: "CAN-mcp-impact", direction: "outgoing" },
      id: 3
    ).dig("result", "structuredContent")
    expect(absent).to include("status" => "not_found")

    projector = Coordinator::Container["projectors.candidates_v1"]
    projector.call(candidate_events.first)
    partial = call_tool(
      "candidate_impact_get",
      { candidate_id: "CAN-mcp-impact", direction: "outgoing" },
      id: 4
    ).dig("result", "structuredContent")
    expect(partial).to include(
      "status" => "ok",
      "data" => include(
        "page" => include("impact_surface" => nil, "relationships" => [])
      )
    )

    candidate_events.drop(1).each { projector.call(_1) }
    available = call_tool(
      "candidate_impact_get",
      { candidate_id: "CAN-mcp-impact", direction: "outgoing", limit: 20 },
      id: 5
    ).dig("result", "structuredContent")
    expect(available).to include(
      "status" => "ok",
      "data" => include(
        "page" => include(
          "direction" => "outgoing",
          "impact_surface" => include(
            "evidence_status" => "attributed_unverified",
            "evidence" => include(
              "causation_id" => surface.causation_id,
              "correlation_id" => surface.correlation_id
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

  it "rejects an empty surface before Task allocation" do
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
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end
end

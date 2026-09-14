# frozen_string_literal: true

RSpec.describe "VER-02 MCP compatibility assessments", :event_store do
  ASSESSMENT_PROTOCOL_VERSION = "2026-07-28"
  ASSESSMENT_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "submits exact attributed evidence through a durable traced Task" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-assessment")
    claim = CandidateObligationScenario.claim_obligation(created:, prefix: "mcp-assessment")
    arguments = assessment_arguments(
      created:,
      claim:,
      command_id: "cmd-mcp-assessment"
    )

    submitted_result = call_tool(arguments, id: 1)
    task_id = submitted_result.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(CommandTraceFixture.events(task_id, event_store:).map(&:type)).to eq([ "CommandRegistered" ])

    execute_task(task_id)
    completed = task_request(task_id, id: 2)
    content = completed.dig("result", "result", "structuredContent")
    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false)
    expect(content).to include(
      "status" => "ok",
      "data" => include(
        "obligation_id" => created.fetch(:result).obligation_id,
        "evidence_id" => match(Coordinator::Shared::Types::UUID_V7_PATTERN),
        "evidence_kind" => "combined_tests",
        "conclusion" => "passed",
        "status" => "open"
      )
    )

    submitted, started, task_completed = task_events(task_id)
    evidence = evidence_events(created).sole
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    expect(evidence.causation_id).to eq(started.id)
    command_facts = CommandTraceFixture.domain_events(task_id, event_store:)
    expect(command_terminal.causation_id).to eq(command_facts.last.id)
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect([ submitted, started, evidence, command_terminal, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
    expect(evidence.metadata).not_to have_key("correlation_id")
  end

  it "completes an authoritative claim-owner denial as an isError Task result" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-assessment-owner")
    claim = CandidateObligationScenario.claim_obligation(created:, prefix: "mcp-assessment-owner")
    arguments = assessment_arguments(
      created:,
      claim:,
      command_id: "cmd-mcp-assessment-owner"
    ).merge(actor: { kind: "agent", id: "agent-green" })
    task_id = call_tool(arguments, id: 1).dig("result", "taskId")

    execute_task(task_id)
    denied = task_request(task_id, id: 2)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include(
          "code" => "verification_obligation_claim_not_owned",
          "details" => include(
            "obligation_id" => created.fetch(:result).obligation_id,
            "claimant_id" => "agent-blue"
          )
        )
      )
    )
    expect(evidence_events(created)).to be_empty
    expect(command_events(arguments.fetch(:command_id))).to be_empty
  end

  it "requires Tasks and rejects invalid non-passed evidence before Task allocation" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-assessment-input")
    claim = CandidateObligationScenario.claim_obligation(created:, prefix: "mcp-assessment-input")
    arguments = assessment_arguments(
      created:,
      claim:,
      command_id: "cmd-mcp-assessment-input",
      conclusion: "failed"
    )
    arguments[:assessment][:findings] = []

    missing_capability = call_tool(arguments, id: 1, capable: false)
    invalid = call_tool(arguments, id: 2)

    expect(missing_capability.dig("error", "code")).to eq(-32_003)
    expect(missing_capability.dig("error", "data", "requiredCapabilities", "extensions")).to eq(
      ASSESSMENT_TASKS_EXTENSION => {}
    )
    expect(invalid.dig("error", "code")).to eq(-32_602)
    expect(invalid.dig("error", "data", "code")).to eq("invalid_input")
    expect(task_events_for_command(arguments.fetch(:command_id))).to be_empty
  end

  private

  def assessment_arguments(created:, claim:, command_id:, **options)
    CandidateObligationScenario.compatibility_assessment_arguments(
      created:,
      claim:,
      command_id:,
      **options
    )
  end

  def call_tool(arguments, id:, capable: true)
    mcp_request(
      id:,
      method: "tools/call",
      name: "compatibility_assessment_submit",
      params: { name: "compatibility_assessment_submit", arguments: },
      capable:
    )
  end

  def task_request(task_id, id:)
    mcp_request(
      id:,
      method: "tasks/get",
      name: task_id,
      params: { taskId: task_id }
    )
  end

  def mcp_request(id:, method:, name:, params:, capable: true)
    capabilities = capable ? { extensions: { ASSESSMENT_TASKS_EXTENSION => {} } } : {}
    request_params = params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => ASSESSMENT_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => capabilities,
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: request_params),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => ASSESSMENT_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    JSON.parse(session.response.body)
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

  def evidence_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:result).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          VerificationEvidenceSubmitted VerificationObligationSatisfied VerificationObligationFailed
        ],
        maximum_count: 34,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end

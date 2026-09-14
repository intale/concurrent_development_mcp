# frozen_string_literal: true

RSpec.describe "VER-03 MCP verification-obligation waiver", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:protocol_version) { "2026-07-28" }
  let(:tasks_extension) { "io.modelcontextprotocol/tasks" }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "waives one exact obligation through a mandatory durable Task" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-waiver")
    arguments = CandidateObligationScenario.waiver_arguments(
      created:,
      command_id: "cmd-mcp-waiver"
    )

    submitted = call_tool(arguments, id: 1)
    task_id = submitted.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    execute_task(task_id)
    completed = task_request(task_id, id: 2)

    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result")).to include(
      "isError" => false,
      "structuredContent" => include(
        "status" => "ok",
        "data" => include(
          "obligation_id" => created.fetch(:payload).obligation_id,
          "previous_status" => "open",
          "status" => "waived",
          "reason" => include("code" => "accepted_risk")
        )
      )
    )
    submitted_event, started, task_completed = task_events(task_id)
    waiver = waiver_events(created).sole
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    expect(waiver.causation_id).to eq(started.id)
    command_facts = CommandTraceFixture.domain_events(task_id, event_store:)
    expect(command_terminal.causation_id).to eq(command_facts.last.id)
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect([ submitted_event, started, waiver, command_terminal, task_completed ].map(&:correlation_id).uniq)
      .to eq([ submitted_event.correlation_id ])
  end

  it "returns terminal denials without target receipts" do
    created = CandidateObligationScenario.create_obligation(
      prefix: "mcp-waiver-denied",
      required_evidence: [ "combined_tests" ]
    )
    claim = CandidateObligationScenario.claim_obligation(created:, prefix: "mcp-waiver-denied")
    receipt = CandidateObligationScenario.submit_compatibility_assessment(
      created:,
      claim:,
      command_id: "cmd-mcp-waiver-satisfied-evidence"
    )
    CandidateObligationScenario.process_compatibility_outcome(receipt)
    arguments = CandidateObligationScenario.waiver_arguments(
      created:,
      command_id: "cmd-mcp-waiver-satisfied"
    )

    task_id = call_tool(arguments, id: 1).dig("result", "taskId")
    execute_task(task_id)
    denied = task_request(task_id, id: 2)

    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include("code" => "verification_obligation_terminal")
      )
    )
    expect(CommandTraceFixture.events(task_id, event_store:).map(&:type)).to eq(
      [ "CommandRegistered", "CommandRejected" ]
    )
  end

  it "requires Tasks and validates user attribution before allocating one" do
    arguments = {
      command_id: "cmd-mcp-waiver-invalid",
      actor: { kind: "user", id: "user-label" },
      obligation_id: "verification-obligation-v1:missing",
      obligation_validity_input_digest: "sha256:#{"a" * 64}",
      reason: { code: "accepted_risk", summary: "Accept exact risk." }
    }
    missing_capability = call_tool(arguments, id: 1, capable: false)
    invalid = call_tool(
      arguments.merge(actor: { kind: "agent", id: "agent-a" }),
      id: 2
    )

    expect(missing_capability.dig("error", "code")).to eq(-32_003)
    expect(missing_capability.dig("error", "data", "requiredCapabilities", "extensions"))
      .to eq(tasks_extension => {})
    expect(invalid.dig("result", "isError")).to be(true)
    expect(task_events_for_command(arguments.fetch(:command_id))).to be_empty
  end

  private

  def call_tool(arguments, id:, capable: true)
    mcp_request(
      id:,
      method: "tools/call",
      name: "verification_obligation_waive",
      params: { name: "verification_obligation_waive", arguments: },
      capable:
    )
  end

  def task_request(task_id, id:)
    mcp_request(id:, method: "tasks/get", name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, name:, params:, capable: true)
    capabilities = capable ? { extensions: { tasks_extension => {} } } : {}
    request_params = params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => protocol_version,
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
        "MCP-Protocol-Version" => protocol_version,
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

  def waiver_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:payload).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationWaived" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end

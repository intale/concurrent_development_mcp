# frozen_string_literal: true

RSpec.describe "VER-01 MCP verification-obligation claims", :event_store do
  CLAIM_PROTOCOL_VERSION = "2026-07-28"
  CLAIM_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "claims through a durable traced Task and returns the server claim identity and fence" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-claim")
    obligation_id = created.fetch(:result).obligation_id
    arguments = claim_arguments(obligation_id:, command_id: "cmd-mcp-claim-1", agent_id: "agent-blue")

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
        "obligation_id" => obligation_id,
        "claim_id" => match(Coordinator::Shared::Types::UUID_V7_PATTERN),
        "claimant_id" => "agent-blue",
        "fencing_token" => 1
      )
    )

    submitted, started, task_completed = task_events(task_id)
    claim = claim_events(obligation_id).sole
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    expect(claim.causation_id).to eq(started.id)
    expect(command_terminal.causation_id).to eq(started.id)
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect([ submitted, started, claim, command_terminal, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
    expect(claim.metadata).not_to have_key("correlation_id")
  end

  it "completes active contention as an isError conflict without a target receipt" do
    created = CandidateObligationScenario.create_obligation(prefix: "mcp-claim-conflict")
    obligation_id = created.fetch(:result).obligation_id
    first = claim_arguments(obligation_id:, command_id: "cmd-mcp-claim-blue", agent_id: "agent-blue")
    second = claim_arguments(obligation_id:, command_id: "cmd-mcp-claim-green", agent_id: "agent-green")
    first_task = call_tool(first, id: 1).dig("result", "taskId")
    execute_task(first_task)
    second_task = call_tool(second, id: 2).dig("result", "taskId")

    execute_task(second_task)
    denied = task_request(second_task, id: 3)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include(
          "code" => "verification_obligation_already_claimed",
          "details" => include(
            "obligation_id" => obligation_id,
            "claimant_id" => "agent-blue",
            "fencing_token" => 1
          )
        )
      )
    )
    expect(claim_events(obligation_id).length).to eq(1)
    expect(CommandTraceFixture.events(second_task, event_store:).map(&:type)).to eq(
      [ "CommandRegistered", "CommandRejected" ]
    )
  end

  it "requires Tasks and rejects an invalid duration before allocating one" do
    arguments = claim_arguments(
      obligation_id: "obl-input-gate",
      command_id: "cmd-mcp-claim-invalid",
      agent_id: "agent-blue"
    )
    missing_capability = call_tool(arguments, id: 1, capable: false)
    invalid = call_tool(arguments.merge(claim_duration_seconds: 29), id: 2)

    expect(missing_capability.dig("error", "code")).to eq(-32_003)
    expect(missing_capability.dig("error", "data", "requiredCapabilities", "extensions")).to eq(
      CLAIM_TASKS_EXTENSION => {}
    )
    expect(invalid.dig("result", "isError")).to be(true)
    expect(task_events_for_command(arguments.fetch(:command_id))).to be_empty
  end

  private

  def claim_arguments(obligation_id:, command_id:, agent_id:)
    {
      command_id:,
      actor: { kind: "agent", id: agent_id },
      obligation_id:,
      claim_duration_seconds: 300
    }
  end

  def call_tool(arguments, id:, capable: true)
    mcp_request(
      id:,
      method: "tools/call",
      name: "verification_obligation_claim",
      params: { name: "verification_obligation_claim", arguments: },
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
    capabilities = capable ? { extensions: { CLAIM_TASKS_EXTENSION => {} } } : {}
    request_params = params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => CLAIM_PROTOCOL_VERSION,
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
        "MCP-Protocol-Version" => CLAIM_PROTOCOL_VERSION,
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

  def claim_events(obligation_id)
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationClaimed" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_HISTORY)
  end
end

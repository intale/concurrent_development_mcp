# frozen_string_literal: true

RSpec.describe "GDN-02/03 MCP interpretation lifecycle" do
  INTERPRETATION_PROTOCOL_VERSION = "2026-07-28"
  INTERPRETATION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:arguments) do
    InterpretationInput.build(
      command_id: "cmd-mcp-interpretation",
      interpretation_id: "I-mcp-interpretation",
      source_message_id: "M-mcp-interpretation",
      effect: "forbid",
      modality: "must_not",
      enforcement: InterpretationInput.advisory_enforcement.merge(
        level: "merge_gate",
        on_violation: "block"
      )
    )
  end

  before(:each, :event_store) do
    Coordinator::Write::Operations::ExecuteRecordGuidance.new(event_store:).call(
      command_id: "cmd-mcp-interpretation-source",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-mcp-interpretation",
      conversation_id: "C-mcp-interpretation",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "018f0f4d-4e45-7abc-8def-000000000741" ],
        change_set_id: "CS-1",
        work_item_id: "W-1",
        attempt_id: nil
      }
    ).value!
  end

  it "records an atomic source-bound proposal Task", :event_store do
    created = call_tool("decision_interpretation_propose", arguments, id: 1)
    task_id = created.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])

    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 2)
    result = completed.dig("result", "result", "structuredContent")
    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false)
    expect(result).to include(
      "status" => "ok",
      "data" => include(
        "interpretation_id" => "I-mcp-interpretation",
        "source_message_id" => "M-mcp-interpretation",
        "assessment" => include("status" => "confirmation_required")
      )
    )

    submitted, started, task_completed = task_events(task_id)
    proposal, clarification = interpretation_events
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    source = guidance_events.sole
    expect([ proposal, clarification ].map(&:type)).to eq(%w[
      DecisionInterpretationProposed
      DecisionClarificationRequired
    ])
    expect([ proposal, clarification ].map(&:stream_revision)).to eq([ 0, 1 ])
    expect([ proposal, clarification, command_terminal ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect(
      [ submitted, started, proposal, clarification, command_terminal, task_completed ]
        .map(&:correlation_id).uniq
    ).to eq([ submitted.correlation_id ])
    expect(proposal.correlation_id).not_to eq(source.correlation_id)
    expect(proposal.data.fetch("source_event")).to include(
      "event_id" => source.id,
      "type" => source.type,
      "stream_revision" => source.stream_revision
    )
    expect([ proposal, clarification, command_terminal ]).to all(
      satisfy { !_1.metadata.key?("causation_id") && !_1.metadata.key?("correlation_id") }
    )

    duplicate_arguments = arguments.merge(command_id: "cmd-mcp-interpretation-duplicate")
    duplicate_task = call_tool(
      "decision_interpretation_propose",
      duplicate_arguments,
      id: 3
    ).dig("result", "taskId")
    execute_task(duplicate_task)
    duplicate = task_request("tasks/get", duplicate_task, id: 4)
    expect(duplicate.dig("result", "status")).to eq("completed")
    expect(duplicate.dig("result", "result", "isError")).to be(true)
    expect(duplicate.dig("result", "result", "structuredContent", "data", "code")).to eq(
      "interpretation_already_proposed"
    )
    expect(interpretation_events.length).to eq(2)
  end

  it "accepts a proposal through a traced Task", :event_store do
    proposal_task_id = call_tool(
      "decision_interpretation_propose",
      arguments,
      id: 1
    ).dig("result", "taskId")
    execute_task(proposal_task_id)
    adjudication = InterpretationInput.adjudication(
      command_id: "cmd-mcp-interpretation-accept",
      source_message_id: "M-mcp-interpretation",
      interpretation_id: "I-mcp-interpretation"
    )
    created = call_tool("decision_interpretation_adjudicate", adjudication, id: 2)
    task_id = created.dig("result", "taskId")
    expect(task_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(task_events(task_id).map(&:type)).to eq([ "CoordinationTaskSubmitted" ])

    execute_task(task_id)
    completed = task_request("tasks/get", task_id, id: 3)
    result = completed.dig("result", "result", "structuredContent")
    expect(completed.dig("result", "status")).to eq("completed")
    expect(completed.dig("result", "result", "isError")).to be(false)
    expect(result).to include(
      "status" => "ok",
      "data" => include(
        "interpretation_id" => "I-mcp-interpretation",
        "action" => "accept",
        "outcome" => "accepted_for_activation",
        "policy_status" => "proposal_only",
        "slot" => include(
          "compound_marker" => include(
            "marker" => a_string_starting_with("compound:interpretation-slot:v2|")
          )
        )
      )
    )

    submitted, started, task_completed = task_events(task_id)
    acceptance = interpretation_events.find { _1.type == "DecisionInterpretationAccepted" }
    command_terminal = CommandTraceFixture.terminal(task_id, event_store:)
    expect(acceptance).not_to be_nil
    expect([ acceptance, command_terminal ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(command_terminal.id)
    expect([ submitted, started, acceptance, command_terminal, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )
    expect(acceptance.markers).to include(
      "resolution-strategy:single_choice",
      a_string_starting_with("compound:interpretation-slot:v2|")
    )
  end

  it "serves a directly persisted accepted interpretation", :read_model do
    acceptance_event = {
      "event_id" => SecureRandom.uuid_v7,
      "type" => "DecisionInterpretationAccepted",
      "stream_context" => "HumanGuidance",
      "stream_name" => "DecisionInterpretation",
      "stream_id" => "M-mcp-interpretation",
      "stream_revision" => 2
    }
    create(
      :coordinator_read_decision_interpretation,
      interpretation_id: "I-mcp-interpretation",
      message_id: "M-mcp-interpretation",
      lifecycle_status: "accepted",
      stream_id: "M-mcp-interpretation",
      adjudication: {
        "action" => "accept",
        "outcome" => "accepted_for_activation",
        "rationale" => nil,
        "clarification" => nil,
        "slot" => nil,
        "actor" => { "kind" => "user", "id" => "user-label", "authenticated" => false },
        "event" => acceptance_event,
        "adjudicated_at" => "2026-08-30T12:01:00.000000Z",
        "causation_id" => SecureRandom.uuid_v7,
        "correlation_id" => SecureRandom.uuid_v7
      }
    )
    observed = interpretation_list(id: 4).dig("data", "page", "interpretations").sole
    expect(observed).to include(
      "lifecycle_status" => "accepted",
      "policy_status" => "proposal_only",
      "adjudication" => include(
        "action" => "accept",
        "outcome" => "accepted_for_activation",
        "event" => include("event_id" => acceptance_event.fetch("event_id"))
      )
    )
  end

  it "returns missing-proposal denial as a Task result and rejects malformed input before allocation", :event_store do
    missing_arguments = InterpretationInput.adjudication(
      command_id: "cmd-mcp-interpretation-missing",
      source_message_id: "M-mcp-interpretation",
      interpretation_id: "I-missing"
    )
    missing_task_id = call_tool(
      "decision_interpretation_adjudicate",
      missing_arguments,
      id: 1
    ).dig("result", "taskId")
    execute_task(missing_task_id)
    missing = task_request("tasks/get", missing_task_id, id: 2)

    expect(missing.dig("result", "status")).to eq("completed")
    expect(missing.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "denied",
        "data" => include(
          "code" => "interpretation_not_found",
          "details" => include(
            "interpretation_id" => "I-missing",
            "message_id" => "M-mcp-interpretation"
          )
        )
      )
    )
    expect(CommandTraceFixture.events(missing_task_id, event_store:).map(&:type)).to eq(
      [ "CommandRegistered", "CommandRejected" ]
    )

    malformed_arguments = InterpretationInput.adjudication(
      command_id: "cmd-mcp-interpretation-malformed",
      source_message_id: "M-mcp-interpretation",
      interpretation_id: "I-mcp-interpretation",
      clarification: InterpretationInput.clarification
    )
    malformed = call_tool(
      "decision_interpretation_adjudicate",
      malformed_arguments,
      id: 3,
      expected_status: 400
    )

    expect(malformed.dig("error", "code")).to eq(-32_602)
    expect(malformed.dig("error", "data", "code")).to eq("invalid_input")
    expect(malformed.dig("error", "data", "details")).to include("clarification")
    expect(task_events_for_command(malformed_arguments.fetch(:command_id))).to be_empty

    invalid_policy = InterpretationInput.impact_policy(
      level: "verification_gate",
      command_id: "cmd-mcp-impact-policy-invalid",
      interpretation_id: "I-mcp-impact-policy-invalid",
      source_message_id: "M-mcp-interpretation"
    )
    invalid_policy[:proposed_decision][:enforcement][:on_violation] = "warn"
    rejected_policy = call_tool(
      "decision_interpretation_propose",
      invalid_policy,
      id: 4,
      expected_status: 400
    )

    expect(rejected_policy.dig("error", "code")).to eq(-32_602)
    expect(rejected_policy.dig("error", "data", "code")).to eq("invalid_input")
    expect(rejected_policy.dig("error", "data", "details")).to include("proposed_decision")
    expect(task_events_for_command(invalid_policy.fetch(:command_id))).to be_empty
  end

  def call_tool(name, tool_arguments, id:, expected_status: 200)
    mcp_request(
      id:,
      method: "tools/call",
      name:,
      params: { name:, arguments: tool_arguments },
      expected_status:
    )
  end

  def interpretation_list(id:)
    call_tool(
      "decision_interpretation_list",
      { message_id: "M-mcp-interpretation", after_revision: -1, limit: 20 },
      id:
    ).dig("result", "structuredContent")
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, params:, name:, expected_status: 200)
    session.post(
      "/mcp",
      params: JSON.generate(
        jsonrpc: "2.0",
        id:,
        method:,
        params: modern_params(params)
      ),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => INTERPRETATION_PROTOCOL_VERSION,
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
        "io.modelcontextprotocol/protocolVersion" => INTERPRETATION_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { INTERPRETATION_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
    CommandResultFixture.project(task_id, event_store:)
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
            {
              type: "CoordinationTaskSubmitted",
              markers: [ "command:#{command_id}" ]
            }
          ]
        }
      }
    )
  end

  def guidance_events
    event_store.read(
      streams.conversation("C-mcp-interpretation"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: Coordinator::Write::EventQueries::GUIDANCE_MESSAGE_EVENT_TYPES,
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def interpretation_events
    event_store.read(
      streams.interpretation("M-mcp-interpretation"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          DecisionInterpretationProposed
          DecisionClarificationRequired
          DecisionInterpretationAccepted
          DecisionInterpretationRejected
        ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end
end

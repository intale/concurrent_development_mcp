# frozen_string_literal: true

RSpec.describe "DEC-02A MCP Decision correction", :event_store, :read_model do
  CORRECTION_PROTOCOL_VERSION = "2026-07-28"
  CORRECTION_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end

  it "corrects through a traced Task while a stale view stays available and is safely rejected" do
    activated = seed_active_decision
    seed_correction(
      interpretation_id: "I-mcp-correction",
      message_id: "M-mcp-correction",
      suffix: "correction",
      value: InterpretationInput.named_choice("minitest")
    )
    seed_correction(
      interpretation_id: "I-mcp-stale-correction",
      message_id: "M-mcp-stale-correction",
      suffix: "stale-correction",
      value: InterpretationInput.named_choice("test-unit")
    )
    decision_events.each { projector.call(_1) }

    active_view = decision_get(id: 1)
    expected_head = active_view.dig("data", "decision", "current_head", "event")
    expect(expected_head).to include(
      "event_id" => activated.id,
      "type" => "DecisionActivated",
      "stream_revision" => 1
    )

    arguments = correction_arguments(
      command_id: "cmd-mcp-decision-correction",
      interpretation_id: "I-mcp-correction",
      expected_head:
    )
    created = call_tool("decision_correct", arguments, id: 2)
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
        "decision_id" => "D-mcp-decision",
        "interpretation_id" => "I-mcp-correction",
        "outcome" => "corrected",
        "policy_status" => "active",
        "correction_event" => include(
          "type" => "DecisionDefinitionCorrected",
          "stream_revision" => 2
        )
      ),
      "next_actions" => [
        include("tool" => "decision_get", "arguments" => { "decision_id" => "D-mcp-decision" })
      ]
    )

    submitted, started, task_completed = task_events(task_id)
    corrected = decision_events.find { _1.type == "DecisionDefinitionCorrected" }
    correction_facts = [
      corrected,
      *slot_events(result.dig("data", "slot", "slot_id")).select { _1.causation_id == started.id },
      *partition_events.select { _1.causation_id == started.id }
    ]
    completion = command_events(arguments.fetch(:command_id)).sole
    expect(correction_facts.map(&:type)).to eq(%w[
      DecisionDefinitionCorrected
      DecisionSlotHeadChanged
      DecisionPartitionAdvanced
    ])
    expect([ *correction_facts, completion ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(completion.id)
    expect([ submitted, started, *correction_facts, completion, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )

    stale_view = decision_get(id: 4)
    expect(stale_view).to include(
      "status" => "ok",
      "data" => include(
        "decision" => include(
          "interpretation_id" => "I-mcp-decision",
          "correction_count" => 0,
          "current_head" => include("event" => include("event_id" => activated.id))
        )
      )
    )

    stale_arguments = correction_arguments(
      command_id: "cmd-mcp-stale-correction",
      interpretation_id: "I-mcp-stale-correction",
      expected_head:
    )
    stale_task_id = call_tool("decision_correct", stale_arguments, id: 5).dig("result", "taskId")
    execute_task(stale_task_id)
    denied = task_request("tasks/get", stale_task_id, id: 6)
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "conflict",
        "data" => include(
          "code" => "decision_revision_changed",
          "details" => include(
            "expected_head" => include("event_id" => activated.id),
            "current_head" => include("event_id" => corrected.id)
          )
        )
      )
    )
    expect(command_events(stale_arguments.fetch(:command_id))).to be_empty
    expect(decision_events.count { _1.type == "DecisionDefinitionCorrected" }).to eq(1)

    projector.call(corrected)
    projected = decision_get(id: 7)
    expect(projected).to include(
      "status" => "ok",
      "data" => include(
        "decision" => include(
          "interpretation_id" => "I-mcp-correction",
          "correction_count" => 1,
          "correction_rationale" => include("code" => "normalization_corrected"),
          "current_head" => include(
            "event" => include(
              "event_id" => corrected.id,
              "type" => "DecisionDefinitionCorrected",
              "stream_revision" => 2
            )
          )
        )
      )
    )
  end

  it "rejects malformed correction input before allocating a Task" do
    response = call_tool(
      "decision_correct",
      correction_arguments(
        command_id: "cmd-mcp-malformed-correction",
        interpretation_id: "I-mcp-correction",
        expected_head: {
          event_id: "not-a-uuid",
          type: "DecisionActivated",
          stream_context: "HumanGuidance",
          stream_name: "Decision",
          stream_id: "D-mcp-decision",
          stream_revision: 1
        }
      ),
      id: 1
    )

    expect(response.dig("result", "isError")).to be(true)
    expect(response.dig("result", "content").sole.fetch("text")).to include("event_id")
    expect(task_events_for_command("cmd-mcp-malformed-correction")).to be_empty
  end

  def seed_active_decision
    seed_accepted_interpretation(
      interpretation_id: "I-mcp-decision",
      message_id: "M-mcp-decision",
      suffix: "initial",
      value: InterpretationInput.named_choice("rspec"),
      relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "cmd-mcp-decision-activation",
        decision_id: "D-mcp-decision",
        interpretation_id: "I-mcp-decision"
      )
    )
    decision_events.find { _1.type == "DecisionActivated" }
  end

  def seed_correction(interpretation_id:, message_id:, suffix:, value:)
    seed_accepted_interpretation(
      interpretation_id:,
      message_id:,
      suffix:,
      value:,
      relations: {
        corrects: [ "D-mcp-decision" ],
        supersedes: [],
        exception_to: [],
        revokes: []
      }
    )
  end

  def seed_accepted_interpretation(interpretation_id:, message_id:, suffix:, value:, relations:)
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-mcp-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-mcp-#{suffix}",
      source: "mcp_client",
      text: "Use the selected test framework.",
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, InterpretationInput.build(
      command_id: "cmd-mcp-proposal-#{suffix}",
      interpretation_id:,
      source_message_id: message_id,
      source_span: nil,
      value:,
      relations:
    ))
    execute(Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, InterpretationInput.adjudication(
      command_id: "cmd-mcp-adjudication-#{suffix}",
      source_message_id: message_id,
      interpretation_id:
    ))
  end

  def correction_arguments(command_id:, interpretation_id:, expected_head:)
    InterpretationInput.correction(
      command_id:,
      decision_id: "D-mcp-decision",
      interpretation_id:,
      expected_head:
    )
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def decision_get(id:)
    call_tool("decision_get", { decision_id: "D-mcp-decision" }, id:)
      .dig("result", "structuredContent")
  end

  def call_tool(name, arguments, id:)
    mcp_request(id:, method: "tools/call", name:, params: { name:, arguments: })
  end

  def task_request(method, task_id, id:)
    mcp_request(id:, method:, name: task_id, params: { taskId: task_id })
  end

  def mcp_request(id:, method:, params:, name:)
    session.post(
      "/mcp",
      params: JSON.generate(jsonrpc: "2.0", id:, method:, params: modern_params(params)),
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => CORRECTION_PROTOCOL_VERSION,
        "Mcp-Method" => method,
        "Mcp-Name" => name
      }
    )
    expect(session.response.status).to eq(200), session.response.body
    JSON.parse(session.response.body)
  end

  def modern_params(params)
    params.merge(
      _meta: {
        "io.modelcontextprotocol/protocolVersion" => CORRECTION_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { CORRECTION_TASKS_EXTENSION => {} }
        },
        "io.modelcontextprotocol/clientInfo" => { name: "rspec", version: "1.0" }
      }
    )
  end

  def execute_task(task_id)
    submitted = task_events(task_id).find { _1.type == "CoordinationTaskSubmitted" }
    Coordinator::Container["process_managers.coordination_task_executor"].call(submitted)
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

  def decision_events
    event_store.read(
      streams.decision("D-mcp-decision"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionRecorded DecisionActivated DecisionDefinitionCorrected],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def slot_events(slot_id)
    event_store.read(
      streams.decision_slot(slot_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[DecisionSlotOpened DecisionSlotHeadChanged],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def partition_events
    event_store.read(
      streams.decision_partition("repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "DecisionPartitionAdvanced" ],
        maximum_count: 10,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def projector
    Coordinator::Container["projectors.decision_governance_v1"]
  end
end

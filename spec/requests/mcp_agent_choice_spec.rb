# frozen_string_literal: true

RSpec.describe "CHO-01 MCP agent choice recording" do
  CHOICE_PROTOCOL_VERSION = "2026-07-28"
  CHOICE_TASKS_EXTENSION = "io.modelcontextprotocol/tasks"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:repository_id) { "018f0f4d-4e45-7abc-8def-000000000751" }
  let(:session) do
    ActionDispatch::Integration::Session.new(Rails.application).tap do |integration|
      integration.host! "localhost"
    end
  end
  let(:context) do
    {
      repository_id:,
      change_set_id: "CS-mcp-choice",
      work_item_id: "W-mcp-choice",
      attempt_id: "A-mcp-choice",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/order_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    }
  end

  before(:each, :event_store) { seed_active_attempt }

  it "records an authoritative choice through a traced Task", :event_store do
    decision_context = resolve_context(id: 1)
    arguments = choice_arguments(
      command_id: "cmd-mcp-choice",
      choice_id: "CHO-mcp-choice",
      decision_context:
    )

    created = call_tool("agent_choice_record", arguments, id: 2)
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
      "command_id" => "cmd-mcp-choice",
      "data" => include(
        "choice_id" => "CHO-mcp-choice",
        "choice_type" => "testing.framework",
        "outcome" => "accepted",
        "assessment_basis" => "no_policy",
        "based_on_decisions" => [],
        "warnings" => []
      )
    )

    submitted, started, task_completed = task_events(task_id)
    choice_facts = choice_events("CHO-mcp-choice")
    completion = command_events("cmd-mcp-choice").sole
    expect(choice_facts.map(&:type)).to eq(%w[AgentChoiceRecorded AgentChoiceAccepted])
    expect([ *choice_facts, completion ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(task_completed.causation_id).to eq(completion.id)
    expect([ submitted, started, *choice_facts, completion, task_completed ].map(&:correlation_id).uniq).to eq(
      [ submitted.correlation_id ]
    )

  end

  it "serves directly persisted recorded and accepted Choice views", :read_model do
    recorded = create(
      :coordinator_read_agent_choice,
      choice_id: "CHO-mcp-choice-recorded",
      recorded_causation_id: SecureRandom.uuid_v7,
      recorded_correlation_id: SecureRandom.uuid_v7
    )
    recorded_view = call_tool("agent_choice_get", { choice_id: recorded.choice_id }, id: 4)
      .dig("result", "structuredContent", "data", "choice")
    expect(recorded_view).to include(
      "choice_id" => recorded.choice_id,
      "observation_status" => "recorded",
      "selected" => include("option_id" => "rspec"),
      "assessment" => nil,
      "accepted" => nil,
      "recorded" => include(
        "event" => include("event_id" => recorded.recorded_event.fetch("event_id")),
        "markers" => include("choice:#{recorded.choice_id}"),
        "causation_id" => recorded.recorded_causation_id,
        "correlation_id" => recorded.recorded_correlation_id
      )
    )

    accepted = create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id: "CHO-mcp-choice",
      accepted_causation_id: SecureRandom.uuid_v7,
      accepted_correlation_id: SecureRandom.uuid_v7
    )
    accepted_view = call_tool("agent_choice_get", { choice_id: accepted.choice_id }, id: 5)
      .dig("result", "structuredContent", "data", "choice")
    expect(accepted_view).to include(
      "observation_status" => "accepted",
      "assessment" => include("basis" => "no_policy"),
      "accepted" => include(
        "event" => include("event_id" => accepted.accepted_event.fetch("event_id")),
        "causation_id" => accepted.accepted_causation_id,
        "correlation_id" => accepted.accepted_correlation_id
      )
    )
    expect(accepted_view.keys & %w[fresh pending projection_status]).to be_empty
  end

  it "serves stale context but rejects its later command without choice facts", :event_store do
    stale_context = resolve_context(id: 1)
    seed_active_decision
    arguments = choice_arguments(
      command_id: "cmd-mcp-choice-stale",
      choice_id: "CHO-mcp-choice-stale",
      decision_context: stale_context
    )

    task_id = call_tool("agent_choice_record", arguments, id: 2).dig("result", "taskId")
    execute_task(task_id)
    denied = task_request("tasks/get", task_id, id: 3)

    expect(denied.dig("result", "status")).to eq("completed")
    expect(denied.dig("result", "result")).to include(
      "isError" => true,
      "structuredContent" => include(
        "status" => "stale_context",
        "data" => include(
          "code" => "stale_decision_context",
          "details" => include(
            "changed_partition_ids" => [ "repo:#{repository_id}:testing" ]
          )
        ),
        "next_actions" => [
          include(
            "tool" => "decision_resolve",
            "arguments" => include(
              "topic_id" => "testing.framework",
              "context" => include("attempt_id" => "A-mcp-choice")
            )
          )
        ]
      )
    )
    expect(choice_events("CHO-mcp-choice-stale")).to be_empty
    expect(command_events("cmd-mcp-choice-stale")).to be_empty
  end

  it "rejects a forged context digest before allocating a Task", :event_store do
    decision_context = resolve_context(id: 1)
    decision_context["digest"] = "sha256:#{'f' * 64}"
    arguments = choice_arguments(
      command_id: "cmd-mcp-choice-forged",
      choice_id: "CHO-mcp-choice-forged",
      decision_context:
    )

    response = call_tool("agent_choice_record", arguments, id: 2, expected_status: 400)

    expect(response.dig("error", "code")).to eq(-32_602)
    expect(response.dig("error", "data", "details", "decision_context", "digest")).to eq(
      [ "must match the canonical document" ]
    )
    expect(task_events_for_command(arguments.fetch(:command_id))).to be_empty
  end

  def seed_active_attempt
    RepositoryScenario.register(
      event_store:,
      key: "mcp-choice",
      repository_id:,
      scope: "project:test/mcp-choice"
    )
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "seed-mcp-choice-change-set",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-mcp-choice",
      goal: "Record a significant implementation choice",
      acceptance_criteria: [ "The choice retains authoritative policy evidence" ]
    })
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-mcp-choice-work-item",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-mcp-choice",
      work_item_id: "W-mcp-choice",
      repository_id:,
      goal: "Select a testing framework",
      acceptance_criteria: [ "The selected framework is recorded" ]
    })
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "seed-mcp-choice-activation",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-mcp-choice"
    })
    activation = event_store.read(
      streams.change_set("CS-mcp-choice"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "seed-mcp-choice-attempt",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-mcp-choice",
      work_item_id: "W-mcp-choice",
      attempt_id: "A-mcp-choice",
      base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
    })
  end

  def seed_active_decision
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "seed-mcp-choice-guidance",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-mcp-choice",
      conversation_id: "C-mcp-choice",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ repository_id ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, InterpretationInput.build(
      command_id: "seed-mcp-choice-proposal",
      interpretation_id: "I-mcp-choice",
      source_message_id: "M-mcp-choice"
    ))
    execute(Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation, InterpretationInput.adjudication(
      command_id: "seed-mcp-choice-adjudication",
      source_message_id: "M-mcp-choice",
      interpretation_id: "I-mcp-choice"
    ))
    execute(Coordinator::Write::Operations::ExecuteActivateDecision, InterpretationInput.activation(
      command_id: "seed-mcp-choice-decision",
      decision_id: "D-mcp-choice",
      interpretation_id: "I-mcp-choice"
    ))
  end

  def resolve_context(id:)
    response = call_tool(
      "decision_resolve",
      { topic_id: "testing.framework", context: },
      id:
    )
    result = response.dig("result", "structuredContent")
    expect(result.fetch("status")).to eq("ok")
    result.dig("data", "decision_context")
  end

  def choice_arguments(command_id:, choice_id:, decision_context:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      choice_id:,
      choice_type: "testing.framework",
      selected: { option_id: "rspec", summary: "RSpec" },
      alternatives: [ { option_id: "minitest", summary: "Minitest" } ],
      reason_summary: "Use the framework that best fits the current coordination policy.",
      context:,
      decision_context:
    }
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
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
        "MCP-Protocol-Version" => CHOICE_PROTOCOL_VERSION,
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
        "io.modelcontextprotocol/protocolVersion" => CHOICE_PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities" => {
          extensions: { CHOICE_TASKS_EXTENSION => {} }
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

  def choice_events(choice_id)
    event_store.read(streams.agent_choice(choice_id), Coordinator::Write::EventQueries::AGENT_CHOICE_EXISTENCE)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end

# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteRecordAgentChoice, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  before { seed_active_attempt }

  it "records and accepts an exact no-policy choice atomically and replays it" do
    input = choice_input(decision_context: authoritative_context)

    original = operation.call(input)
    replay = operation.call(input)

    expect(original).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(original.value!.data).to have_attributes(
      choice_id: "CHO-1",
      choice_type: "testing.framework",
      outcome: "accepted",
      assessment_basis: "no_policy",
      based_on_decisions: [],
      warnings: []
    )
    expect(choice_events.map(&:type)).to eq(%w[AgentChoiceRecorded AgentChoiceAccepted])
    expect(choice_events.map(&:stream_revision)).to eq([ 0, 1 ])
    expect(choice_events).to all(
      have_attributes(
        markers: include(
          "choice:CHO-1",
          "choice-type:testing.framework",
          "attempt:A-CHO",
          "repository:billing",
          "command:cmd-choice-1",
          "decision-partition:repo:billing:testing",
          "decision-partition:changeset:CS-CHO:testing",
          "decision-partition:workitem:W-CHO:testing",
          "decision-partition:attempt:A-CHO:testing"
        )
      )
    )
    expect(command_events("cmd-choice-1").length).to eq(1)
  end

  it "accepts an advisory violation with exact Decision evidence" do
    seed_active_decision
    context = authoritative_context

    result = operation.call(
      choice_input(
        decision_context: context,
        selected: { option_id: "minitest", summary: "Minitest" }
      )
    )

    expect(result).to be_success
    expect(result.value!.data).to have_attributes(
      assessment_basis: "advisory_violation",
      based_on_decisions: contain_exactly(have_attributes(decision_id: "D-CHO")),
      warnings: contain_exactly(a_string_starting_with("decision-warning:D-CHO:"))
    )
    expect(choice_events.first.markers).to include("decision:D-CHO")
  end

  it "denies a blocking policy without AgentChoice or Command facts" do
    seed_active_decision(
      enforcement: {
        level: "implementation_gate",
        retroactivity: "future_only",
        on_violation: "block"
      }
    )

    result = operation.call(
      choice_input(
        command_id: "cmd-choice-blocked",
        decision_context: authoritative_context,
        selected: { option_id: "minitest", summary: "Minitest" }
      )
    )

    expect(result.failure).to have_attributes(
      code: :agent_choice_blocked_by_decision,
      details: include(
        selected_option_id: "minitest",
        decision_option_id: "rspec",
        on_violation: "block"
      )
    )
    expect(choice_events).to be_empty
    expect(command_events("cmd-choice-blocked")).to be_empty
  end

  it "rejects an available context made stale by a later Decision activation" do
    stale = authoritative_context
    seed_active_decision

    result = operation.call(
      choice_input(command_id: "cmd-choice-stale", decision_context: stale)
    )

    expect(result.failure).to have_attributes(
      code: :stale_decision_context,
      details: include(changed_partition_ids: [ "repo:billing:testing" ])
    )
    expect(choice_events).to be_empty
    expect(command_events("cmd-choice-stale")).to be_empty
  end

  it "denies a non-owner and leaves the Choice identity available" do
    result = operation.call(
      choice_input(
        command_id: "cmd-choice-owner",
        actor_id: "agent-b",
        decision_context: authoritative_context
      )
    )

    expect(result.failure.code).to eq(:attempt_owner_mismatch)
    expect(choice_events).to be_empty
    expect(command_events("cmd-choice-owner")).to be_empty
  end

  it "serializes concurrent claims for one Choice identity" do
    context = authoritative_context
    inputs = [
      choice_input(command_id: "cmd-choice-race-a", decision_context: context),
      choice_input(command_id: "cmd-choice-race-b", decision_context: context)
    ]

    results = inputs.map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:agent_choice_already_exists)
    expect(choice_events.map(&:type)).to eq(%w[AgentChoiceRecorded AgentChoiceAccepted])
    expect(inputs.sum { command_events(_1.fetch(:command_id)).length }).to eq(1)
  end

  def choice_input(
    decision_context:,
    command_id: "cmd-choice-1",
    actor_id: "agent-a",
    selected: { option_id: "rspec", summary: "RSpec" }
  )
    {
      command_id:,
      actor: { kind: "agent", id: actor_id },
      choice_id: "CHO-1",
      choice_type: "testing.framework",
      selected:,
      alternatives: [ { option_id: "test-unit", summary: "Test::Unit" } ],
      reason_summary: "Use the framework that best fits the current coordination policy.",
      context: query_context.to_h,
      decision_context: decision_context.to_h
    }
  end

  def query_context
    Coordinator::Write::DecisionContexts::QueryContextV1.new(
      workspace_id: nil,
      repository_id: "billing",
      change_set_id: "CS-CHO",
      work_item_id: "W-CHO",
      attempt_id: "A-CHO",
      phase: "implementation",
      language: "ruby",
      paths: [ "spec/models/order_spec.rb" ],
      environment: "test",
      agent_role: "implementer"
    )
  end

  def authoritative_context
    observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(query_context).map do |partition|
      event = event_store.read_grouped(
        streams.decision_partition(partition.partition_id),
        Coordinator::Write::EventQueries::DECISION_PARTITION_LATEST
      ).first
      payload = event && load(event)
      Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
        partition:,
        partition_revision: event&.stream_revision,
        event: event && reference(event),
        active_decisions: payload ? payload.active_decisions : []
      )
    end
    heads = observations.flat_map(&:active_decisions).uniq { [ _1.decision_id, _1.event.event_id ] }
    resolution = Coordinator::Write::DecisionContexts::Resolver.new.call(
      context: query_context,
      observations:,
      decisions: heads.map { current_decision(_1.decision_id) },
      resolved_at: Coordinator::Shared::SystemClock.new.now
    )
    Coordinator::Write::DecisionContexts::Builder.new.call(
      context: query_context,
      observations:,
      resolution:,
      resolved_at: Coordinator::Shared::SystemClock.new.now
    )
  end

  def current_decision(decision_id)
    events = event_store.read_grouped(
      streams.decision(decision_id),
      Coordinator::Write::EventQueries::DECISION_CORRECTION_STATE
    )
    recorded_event = events.find { _1.type == "DecisionRecorded" }
    activated_event = events.find { _1.type == "DecisionActivated" }
    correction_event = events.find { _1.type == "DecisionDefinitionCorrected" }
    recorded = load(recorded_event)
    activation = load(activated_event)
    correction = correction_event && load(correction_event)
    head_event = correction_event || activated_event
    Coordinator::Write::Decisions::DecisionCurrentStateV1.new(
      decision_id:,
      definition: correction ? correction.definition : recorded.definition,
      head: Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id:,
        decision_revision: head_event.stream_revision,
        event: reference(head_event)
      ),
      slot: correction ? correction.slot : activation.slot,
      partitions: correction ? correction.partitions : activation.partitions
    )
  end

  def seed_active_attempt
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "seed-choice-change-set",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-CHO",
      goal: "Record significant implementation choices",
      acceptance_criteria: [ "Choices retain authoritative policy evidence" ]
    })
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "seed-choice-work-item",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-CHO",
      work_item_id: "W-CHO",
      repository_id: "billing",
      goal: "Implement the selected testing framework",
      acceptance_criteria: [ "The selected framework is recorded" ]
    })
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "seed-choice-activation",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-CHO"
    })
    activation = event_store.read(
      streams.change_set("CS-CHO"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "seed-choice-attempt",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-CHO",
      work_item_id: "W-CHO",
      attempt_id: "A-CHO",
      base_snapshots: [ { repository_id: "billing", commit_oid: "a" * 40 } ]
    })
  end

  def seed_active_decision(enforcement: InterpretationInput.advisory_enforcement)
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "seed-choice-guidance",
      actor: { kind: "user", id: "user-label" },
      message_id: "M-CHO",
      conversation_id: "C-CHO",
      source: "mcp_client",
      text: "Use RSpec.",
      anchors: {
        repository_ids: [ "billing" ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation,
      InterpretationInput.build(
        command_id: "seed-choice-proposal",
        interpretation_id: "I-CHO",
        source_message_id: "M-CHO",
        enforcement:
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation,
      InterpretationInput.adjudication(
        command_id: "seed-choice-adjudication",
        source_message_id: "M-CHO",
        interpretation_id: "I-CHO"
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "seed-choice-decision",
        decision_id: "D-CHO",
        interpretation_id: "I-CHO"
      )
    )
  end

  def execute(operation_class, input)
    result = operation_class.new(event_store:).call(input)
    raise result.failure.inspect if result.failure?

    result.value!
  end

  def choice_events
    event_store.read(
      streams.agent_choice("CHO-1"),
      Coordinator::Write::EventQueries::AGENT_CHOICE_EXISTENCE
    )
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end

  def reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end

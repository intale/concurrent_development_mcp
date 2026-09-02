# frozen_string_literal: true

RSpec.describe "CHO-02 AgentChoice impact scan operations", :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "starts one active-Attempt scan from exact activation evidence and replays without duplicate facts" do
    source = seed_activation(retroactivity: "active_attempts", suffix: "active")
    invocation = start_invocation(source)

    original = start_operation.call(invocation)
    replay = start_operation.call(invocation)

    expect(original).to be_success
    expect(replay.failure).to have_attributes(code: :agent_choice_impact_scan_already_decided)
    payload = load(original.value!)
    expect(payload).to have_attributes(
      scan_id: invocation.command.scan_id,
      from_position: 0,
      to_position: source.global_position,
      page_size: 50,
      decision_change: have_attributes(
        source_event: reference(source),
        change_kind: "activated",
        retroactivity: "active_attempts",
        affected_partitions: contain_exactly(have_attributes(partition_id: "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing"))
      )
    )
    expect(original.value!).to have_attributes(
      causation_id: invocation.caused_by.id,
      correlation_id: source.correlation_id
    )
    expect(scan_events(invocation.command.scan_id).map(&:type)).to eq([ "AgentChoiceImpactScanStarted" ])
  end

  it "records an explicit skipped scan for future-only Choice scope" do
    source = seed_activation(retroactivity: "future_only", suffix: "future")
    invocation = start_invocation(source)

    result = start_operation.call(invocation)

    expect(result).to be_success
    expect(load(result.value!)).to have_attributes(
      reason: "future_only",
      decision_change: have_attributes(retroactivity: "future_only")
    )
    expect(scan_state(invocation.command.scan_id)).to have_attributes(
      status: "skipped",
      skip_reason: "future_only"
    )
  end

  it "starts one scan from an exact correction and retains the complete old/new partition union" do
    source = seed_correction(suffix: "correction")
    invocation = start_invocation(source)

    result = start_operation.call(invocation)

    expect(result).to be_success
    expect(load(result.value!).decision_change).to have_attributes(
      source_event: reference(source),
      change_kind: "corrected",
      retroactivity: "active_attempts",
      affected_partitions: contain_exactly(
        have_attributes(partition_id: "repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing"),
        have_attributes(partition_id: "workitem:W-impact-correction:testing")
      )
    )
  end

  it "persists one progress checkpoint and completion with exact Saga tracing" do
    source = seed_activation(retroactivity: "active_attempts", suffix: "progress")
    started = start_operation.call(start_invocation(source)).value!
    first = progress_invocation(
      started,
      previous_from_position: 0,
      last_processed_position: source.global_position - 1,
      page_choice_count: 50,
      has_more: true
    )

    progressed = progress_operation.call(first)
    replay = progress_operation.call(first)
    expect(progressed).to be_success
    expect(replay.failure).to have_attributes(code: :agent_choice_impact_scan_checkpoint_changed)
    expect(progressed.value!).to have_attributes(
      causation_id: first.caused_by.id,
      correlation_id: started.correlation_id
    )

    completion_invocation = progress_invocation(
      progressed.value!,
      previous_from_position: source.global_position,
      last_processed_position: nil,
      page_choice_count: 0,
      has_more: false
    )
    completed = progress_operation.call(completion_invocation)

    expect(completed).to be_success
    expect(completed.value!).to have_attributes(
      causation_id: completion_invocation.caused_by.id,
      correlation_id: started.correlation_id
    )
    expect(load(completed.value!)).to have_attributes(
      final_from_position: source.global_position,
      page_count: 2,
      total_choice_count: 50
    )
    expect(scan_state(started.stream.stream_id)).to have_attributes(
      status: "completed",
      from_position: source.global_position,
      page_count: 2,
      total_choice_count: 50
    )
  end

  it "serializes concurrent progress commands from one checkpoint" do
    source = seed_activation(retroactivity: "active_attempts", suffix: "race")
    started = start_operation.call(start_invocation(source)).value!
    invocation = progress_invocation(
      started,
      previous_from_position: 0,
      last_processed_position: nil,
      page_choice_count: 0,
      has_more: false
    )

    results = Array.new(2) do
      Thread.new { progress_operation.call(invocation) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:agent_choice_impact_scan_not_running)
    expect(scan_events(started.stream.stream_id).map(&:type)).to contain_exactly(
      "AgentChoiceImpactScanStarted",
      "AgentChoiceImpactScanCompleted"
    )
  end

  def start_operation
    Coordinator::Write::Operations::ExecuteStartAgentChoiceImpactScan.new(event_store:)
  end

  def progress_operation
    Coordinator::Write::Operations::ExecuteProgressAgentChoiceImpactScan.new(event_store:)
  end

  def start_invocation(source)
    source_reference = reference(source)
    process_step = Coordinator::Processes::ProcessStepPlanner.new(event_store:).call(
      source_event: source,
      process_name: "agent-choice-decision-impact",
      step_name: "start-impact-scan",
      subject_kind: "decision-change",
      subject_id: source_reference.event_id,
      rule_version: "agent-choice-decision-impact/v1",
      allocate_target_entity: true
    )
    command = Coordinator::Write::Commands::StartAgentChoiceImpactScan.new(
      command_id: process_step.target_command_id,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      scan_id: process_step.target_entity_id!,
      source_event: source_reference,
      source_global_position: source.global_position,
      policy_version: "agent-choice-decision-impact/v1"
    )
    Coordinator::Write::AgentChoiceImpactScanInvocation.new(
      command:,
      source_event: source,
      source_reference:,
      caused_by: process_step.event
    )
  end

  def progress_invocation(
    checkpoint,
    previous_from_position:,
    last_processed_position:,
    page_choice_count:,
    has_more:
  )
    checkpoint_reference = reference(checkpoint)
    process_step = Coordinator::Processes::ProcessStepPlanner.new(event_store:).call(
      source_event: checkpoint,
      process_name: "agent-choice-decision-impact",
      step_name: "progress-impact-scan",
      subject_kind: "impact-scan",
      subject_id: checkpoint.stream.stream_id,
      rule_version: "agent-choice-decision-impact/v1",
      allocate_target_entity: false
    )
    command = Coordinator::Write::Commands::ProgressAgentChoiceImpactScan.new(
      command_id: process_step.target_command_id,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      scan_id: checkpoint.stream.stream_id,
      expected_checkpoint: checkpoint_reference,
      previous_from_position:,
      last_processed_position:,
      page_choice_count:,
      has_more:,
      policy_version: "agent-choice-decision-impact/v1"
    )
    Coordinator::Write::AgentChoiceImpactScanProgressInvocation.new(
      command:,
      checkpoint_event: checkpoint,
      checkpoint_reference:,
      caused_by: process_step.event
    )
  end

  def seed_activation(retroactivity:, suffix:)
    identifiers = seed_accepted_interpretation(
      suffix:,
      enforcement: {
        level: "implementation_gate",
        retroactivity:,
        on_violation: "block"
      }
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "seed-impact-activate-#{suffix}",
        decision_id: identifiers.fetch(:decision_id),
        interpretation_id: identifiers.fetch(:interpretation_id)
      )
    )
    decision_events(identifiers.fetch(:decision_id)).find { _1.type == "DecisionActivated" }
  end

  def seed_correction(suffix:)
    decision_id = "D-impact-#{suffix}"
    base = seed_accepted_interpretation(
      suffix: "#{suffix}-base",
      decision_id:,
      enforcement: InterpretationInput.advisory_enforcement
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "seed-impact-activate-#{suffix}",
        decision_id:,
        interpretation_id: base.fetch(:interpretation_id)
      )
    )
    current_head = reference(decision_events(decision_id).find { _1.type == "DecisionActivated" })
    correction = seed_accepted_interpretation(
      suffix: "#{suffix}-next",
      decision_id:,
      text: "Use Minitest.",
      source_span: { start_character: 4, end_character: 12, text: "Minitest" },
      value: InterpretationInput.named_choice("minitest"),
      scope: InterpretationInput.scope(
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        work_item_id: "W-impact-correction"
      ),
      enforcement: {
        level: "implementation_gate",
        retroactivity: "active_attempts",
        on_violation: "block"
      },
      relations: { corrects: [ decision_id ], supersedes: [], exception_to: [], revokes: [] }
    )
    execute(
      Coordinator::Write::Operations::ExecuteCorrectDecision,
      InterpretationInput.correction(
        expected_head: current_head.to_h,
        command_id: "seed-impact-correct-#{suffix}",
        decision_id:,
        interpretation_id: correction.fetch(:interpretation_id)
      )
    )
    decision_events(decision_id).find { _1.type == "DecisionDefinitionCorrected" }
  end

  def seed_accepted_interpretation(
    suffix:,
    decision_id: "D-impact-#{suffix}",
    text: "Use RSpec.",
    source_span: { start_character: 4, end_character: 9, text: "RSpec" },
    value: InterpretationInput.named_choice("rspec"),
    scope: nil,
    enforcement:,
    relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
  )
    message_id = "M-impact-#{suffix}"
    interpretation_id = "I-impact-#{suffix}"
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "seed-impact-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-impact-#{suffix}",
      source: "mcp_client",
      text:,
      anchors: {
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: nil,
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation,
      InterpretationInput.build(
        command_id: "seed-impact-propose-#{suffix}",
        interpretation_id:,
        source_message_id: message_id,
        source_span:,
        value:,
        scope:,
        enforcement:,
        relations:
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation,
      InterpretationInput.adjudication(
        command_id: "seed-impact-adjudicate-#{suffix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    { decision_id:, interpretation_id: }
  end

  def execute(operation_class, input)
    result = operation_class.new(event_store:).call(input)
    raise result.failure.inspect if result.failure?

    result.value!
  end

  def decision_events(decision_id)
    event_store.read_grouped(
      streams.decision(decision_id),
      Coordinator::Write::EventQueries::DECISION_CORRECTION_STATE
    )
  end

  def scan_events(scan_id)
    event_store.read_grouped(
      streams.agent_choice_impact_scan(scan_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_IMPACT_SCAN_STATE
    )
  end

  def scan_state(scan_id)
    Coordinator::Write::AgentChoiceImpacts::ScanLoader.new(event_store:).call(scan_id).state
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
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
end

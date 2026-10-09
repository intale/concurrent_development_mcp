# frozen_string_literal: true

module AgentChoiceImpactScenario
  module_function

  POLICY_VERSION = "agent-choice-decision-impact/v1"

  def prepare_attempt(prefix:, repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID)
    repository_id = RepositoryScenario.repository_id(repository_id)
    identifiers = AgentChoiceScenario.identifiers(prefix)
    AgentChoiceScenario.seed_active_attempt(
      identifiers:,
      repository_id:,
      actor_id: "agent-a"
    )
    {
      identifiers:,
      context: AgentChoiceScenario.context(identifiers:, repository_id:)
    }
  end

  def record_choice(prepared:, option_id:, choice_id: nil)
    identifiers = prepared.fetch(:identifiers)
    identifiers = identifiers.merge(choice_id:) if choice_id
    context = prepared.fetch(:context)
    decision_context = authoritative_context(context)
    execute(Coordinator::Write::Operations::ExecuteRecordAgentChoice, {
      command_id: "cmd-#{identifiers.fetch(:choice_id)}",
      actor: { kind: "agent", id: "agent-a" },
      choice_id: identifiers.fetch(:choice_id),
      choice_type: "testing.framework",
      selected: { option_id:, summary: option_summary(option_id) },
      alternatives: [
        {
          option_id: option_id == "rspec" ? "minitest" : "rspec",
          summary: option_id == "rspec" ? "Minitest" : "RSpec"
        }
      ],
      reason_summary: "Follow the authoritative testing framework policy.",
      context:,
      decision_context: decision_context.to_h
    })
    accepted = choice_events(identifiers.fetch(:choice_id)).find { _1.type == "AgentChoiceAccepted" }
    {
      identifiers:,
      context:,
      decision_context:,
      accepted:
    }
  end

  def activate_decision(
    suffix:,
    decision_id:,
    option_id:,
    scope:,
    enforcement: blocking_enforcement
  )
    interpretation_id = accepted_interpretation(
      suffix:,
      decision_id:,
      option_id:,
      scope:,
      enforcement:,
      relations: empty_relations
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "cmd-activate-#{suffix}",
        decision_id:,
        interpretation_id:
      )
    )
    decision_event(decision_id, "DecisionActivated")
  end

  def correct_decision(
    suffix:,
    decision_id:,
    option_id:,
    scope:,
    enforcement: blocking_enforcement
  )
    previous_head = reference(current_decision_event(decision_id))
    interpretation_id = accepted_interpretation(
      suffix:,
      decision_id:,
      option_id:,
      scope:,
      enforcement:,
      relations: {
        corrects: [ decision_id ],
        supersedes: [],
        exception_to: [],
        revokes: []
      }
    )
    execute(
      Coordinator::Write::Operations::ExecuteCorrectDecision,
      InterpretationInput.correction(
        expected_head: previous_head.to_h,
        command_id: "cmd-correct-#{suffix}",
        decision_id:,
        interpretation_id:
      )
    )
    decision_event(decision_id, "DecisionDefinitionCorrected")
  end

  def start_scan(source)
    source_reference = reference(source)
    process_step = Coordinator::Processes::ProcessStepPlanner.new(event_store:).call(
      source_event: source,
      process_name: "agent-choice-decision-impact",
      step_name: "start-impact-scan",
      subject_kind: "decision-change",
      subject_id: source_reference.event_id,
      rule_version: POLICY_VERSION,
      allocate_target_entity: true
    )
    command = Coordinator::Write::Commands::StartAgentChoiceImpactScan.new(
      command_id: process_step.target_command_id,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      scan_id: process_step.target_entity_id!,
      source_event: source_reference,
      source_global_position: source.global_position,
      policy_version: POLICY_VERSION
    )
    invocation = Coordinator::Write::AgentChoiceImpactScanInvocation.new(
      command:,
      source_event: source,
      source_reference:,
      caused_by: process_step.event
    )
    Coordinator::Write::Operations::ExecuteStartAgentChoiceImpactScan.new(event_store:).call(invocation).value!
  end

  def assessment_invocation(choice:, source:, caused_by: start_scan(source))
    accepted_reference = reference(choice.fetch(:accepted))
    change = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:).call(source).value!
    process_step = Coordinator::Processes::ProcessStepPlanner.new(event_store:).call(
      source_event: caused_by,
      process_name: "agent-choice-decision-impact",
      step_name: "assess-choice-impact",
      subject_kind: "choice-decision-change",
      subject_id: "#{accepted_reference.event_id}:#{change.source_event.event_id}",
      rule_version: POLICY_VERSION,
      allocate_target_entity: true
    )
    command = Coordinator::Write::Commands::AssessAgentChoiceDecisionImpact.new(
      command_id: process_step.target_command_id,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      assessment_id: process_step.target_entity_id!,
      choice_id: choice.fetch(:identifiers).fetch(:choice_id),
      accepted_choice: accepted_reference,
      decision_change: change,
      policy_version: POLICY_VERSION
    )
    Coordinator::Write::AgentChoiceImpactAssessmentInvocation.new(
      command:,
      caused_by: process_step.event,
      caused_by_reference: process_step.reference
    )
  end

  def authoritative_context(context_input)
    context = Coordinator::Write::DecisionContexts::QueryContextV1.new(context_input)
    observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(context).map do |partition|
      events = event_store.read(
        streams.decision_partition(partition.partition_id),
        Coordinator::Write::EventQueries::DECISION_PARTITION_STATE
      )
      active = {}
      events.each do |event|
        payload = load(event)
        case payload
        when Coordinator::Write::Events::DecisionAddedToPartitionV1
          active[payload.decision_id] = current_decision(payload.decision_id).head
        when Coordinator::Write::Events::DecisionRemovedFromPartitionV1
          active.delete(payload.decision_id)
        end
      end
      event = events.last
      Coordinator::Write::DecisionContexts::PartitionObservationV1.new(
        partition:,
        partition_revision: event&.stream_revision,
        event: event && reference(event),
        active_decisions: active.values.sort_by { _1.decision_id.b }
      )
    end
    heads = observations.flat_map(&:active_decisions).uniq { [ _1.decision_id, _1.event.event_id ] }
    decisions = heads.map { current_decision(_1.decision_id) }
    resolved_at = Coordinator::Shared::SystemClock.new.now
    resolution = Coordinator::Write::DecisionContexts::Resolver.new.call(
      context:,
      observations:,
      decisions:,
      resolved_at:
    )
    Coordinator::Write::DecisionContexts::Builder.new.call(
      context:,
      observations:,
      resolution:,
      resolved_at:
    )
  end

  def current_decision(decision_id)
    events = decision_events(decision_id)
    recorded_event = events.find { _1.type == "DecisionRecorded" }
    activated_event = events.find { _1.type == "DecisionActivated" }
    correction_event = events.find { _1.type == "DecisionDefinitionCorrected" }
    recorded = load(recorded_event)
    correction = correction_event && load(correction_event)
    head_event = correction_event || activated_event
    definition = normalize_definition(correction ? correction.definition : recorded.definition)
    Coordinator::Write::Decisions::DecisionCurrentStateV1.new(
      decision_id:,
      definition:,
      head: Coordinator::Write::Decisions::DecisionHeadV1.new(
        decision_id:,
        decision_revision: head_event.stream_revision,
        event: reference(head_event)
      ),
      slot: nil,
      partitions: Coordinator::Write::Decisions::DecisionPartitionBuilder.new.call(definition)
    )
  end

  def normalize_definition(value)
    Coordinator::Write::Decisions::DecisionDefinitionV1.new(
      document: value,
      digest: Coordinator::Write::CanonicalJson.new.sha256(value.to_h)
    )
  end

  def accepted_interpretation(suffix:, decision_id:, option_id:, scope:, enforcement:, relations:)
    message_id = "M-assessment-#{suffix}"
    interpretation_id = "I-assessment-#{suffix}"
    text = "Use #{option_id}."
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-assessment-#{suffix}",
      source: "mcp_client",
      text:,
      anchors: {
        repository_ids: scope.fetch(:repository_ids),
        change_set_id: scope.fetch(:change_set_id),
        work_item_id: scope.fetch(:work_item_id),
        attempt_id: scope.fetch(:attempt_id)
      }
    })
    execute(
      Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation,
      InterpretationInput.build(
        command_id: "cmd-propose-#{suffix}",
        interpretation_id:,
        source_message_id: message_id,
        source_span: {
          start_character: 4,
          end_character: 4 + option_id.length,
          text: option_id
        },
        statement_kind: "directive",
        effect: "require",
        modality: "must",
        value: InterpretationInput.named_choice(option_id),
        scope:,
        enforcement:,
        relations:
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation,
      InterpretationInput.adjudication(
        command_id: "cmd-adjudicate-#{suffix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    interpretation_id
  end

  def blocking_enforcement
    {
      level: "implementation_gate",
      retroactivity: "active_attempts",
      on_violation: "block"
    }
  end

  def advisory_enforcement
    {
      level: "implementation_gate",
      retroactivity: "active_attempts",
      on_violation: "warn"
    }
  end

  def empty_relations
    { corrects: [], supersedes: [], exception_to: [], revokes: [] }
  end

  def option_summary(option_id)
    option_id == "rspec" ? "RSpec" : option_id.capitalize
  end

  def assessment_events(assessment_id)
    event_store.read(
      streams.agent_choice_impact(assessment_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_IMPACT_ASSESSMENT
    )
  end

  def assessment_history(assessment_id)
    event_store.read(
      streams.agent_choice_impact(assessment_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "AgentChoiceImpactAssessmentRecorded", "AgentChoiceImpactSourceLinked" ],
        maximum_count: 3,
        direction: :asc
      )
    )
  end

  def choice_events(choice_id)
    event_store.read(
      streams.agent_choice(choice_id),
      Coordinator::Write::EventQueries::AGENT_CHOICE_FOR_IMPACT
    )
  end

  def decision_events(decision_id)
    event_store.read_grouped(
      streams.decision(decision_id),
      Coordinator::Write::EventQueries::DECISION_CORRECTION_STATE
    )
  end

  def decision_event(decision_id, type)
    decision_events(decision_id).find { _1.type == type }
  end

  def current_decision_event(decision_id)
    decision_event(decision_id, "DecisionDefinitionCorrected") ||
      decision_event(decision_id, "DecisionActivated")
  end

  def execute(operation_class, input)
    result = operation_class.new(event_store:).call(input)
    raise result.failure.inspect if result.failure?

    result.value!
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

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end
end

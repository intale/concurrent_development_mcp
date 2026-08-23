# frozen_string_literal: true

module AgentChoiceImpactScenario
  module_function

  POLICY_VERSION = "agent-choice-decision-impact/v1"

  def prepare_attempt(prefix:, repository_id: "billing")
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

  def record_choice(prepared:, option_id:)
    identifiers = prepared.fetch(:identifiers)
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
    identity = Coordinator::Write::AgentChoiceImpacts::ScanIdentityBuilder.new.start(
      source_event: source_reference,
      policy_version: POLICY_VERSION
    )
    command = Coordinator::Write::Commands::StartAgentChoiceImpactScan.new(
      command_id: identity,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      scan_id: identity,
      source_event: source_reference,
      source_global_position: source.global_position,
      policy_version: POLICY_VERSION
    )
    invocation = Coordinator::Write::AgentChoiceImpactScanInvocation.new(
      command:,
      source_event: source,
      source_reference:
    )
    Coordinator::Write::Operations::ExecuteStartAgentChoiceImpactScan.new(event_store:).call(invocation).value!
  end

  def assessment_invocation(choice:, source:, caused_by: start_scan(source))
    accepted_reference = reference(choice.fetch(:accepted))
    change = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceBuilder.new(event_store:).call(source).value!
    assessment_id = Coordinator::Write::AgentChoiceImpacts::AssessmentIdentityBuilder.new.call(
      accepted_choice: accepted_reference,
      decision_change: change.source_event,
      policy_version: POLICY_VERSION
    )
    command = Coordinator::Write::Commands::AssessAgentChoiceDecisionImpact.new(
      command_id: assessment_id,
      actor: { kind: "system", id: "agent-choice-decision-impact" },
      assessment_id:,
      choice_id: choice.fetch(:identifiers).fetch(:choice_id),
      accepted_choice: accepted_reference,
      decision_change: change,
      policy_version: POLICY_VERSION
    )
    Coordinator::Write::AgentChoiceImpactAssessmentInvocation.new(
      command:,
      caused_by:,
      caused_by_reference: reference(caused_by)
    )
  end

  def authoritative_context(context_input)
    context = Coordinator::Write::DecisionContexts::QueryContextV1.new(context_input)
    observations = Coordinator::Write::DecisionContexts::PartitionSelector.new.call(context).map do |partition|
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

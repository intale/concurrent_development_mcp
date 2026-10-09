# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoiceImpactsV1, :read_model, :event_store do
  subject(:projector) { described_class.new(assessment_loader:) }

  let(:choice_id) { "CHO-impact-project" }
  let(:attempt_id) { "A-impact-project" }
  let(:assessment_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:decision_changed_at) { decision_source_event.created_at.utc.iso8601(6) }
  let(:assessment_loader) { Coordinator::Read::AgentChoiceImpacts::AssessmentLoader.new(event_store:) }

  it "projects exact assessment sources and invalidation evidence idempotently" do
    create_accepted_choice
    assessment, accepted_link, decision_link, invalidation = impact_events

    [ assessment, accepted_link, decision_link, invalidation ].each do |event|
      projector.call(event)
      projector.call(event)
    end

    impact = impact_repository.page(
      Coordinator::Read::AgentChoiceImpactListQueryV1.new(
        attempt_id:,
        after_global_position: nil,
        limit: 20
      )
    ).items.sole
    expect(impact).to have_attributes(
      outcome: "invalidated",
      reason: "blocking_policy_introduced",
      accepted_choice: accepted_choice_reference,
      decision_changed_at:,
      source_actor: have_attributes(kind: "orchestrator", id: "guidance-host"),
      assessment_evidence: have_attributes(
        event: event_reference(assessment),
        actor: have_attributes(kind: "system", id: "agent-choice-decision-impact"),
        global_position: assessment.global_position,
        causation_id: assessment.causation_id,
        correlation_id: assessment.correlation_id
      )
    )

    choice = Coordinator::Read::Repositories::AgentChoices.new.fetch(choice_id)
    expect(choice).to have_attributes(
      observation_status: "invalidated",
      invalidation: have_attributes(
        reason: "blocking_policy_introduced",
        assessment_event: event_reference(assessment),
        decision_change_event: decision_change.source_event,
        evidence: have_attributes(
          event: event_reference(invalidation),
          causation_id: invalidation.causation_id,
          correlation_id: invalidation.correlation_id
        )
      )
    )
    expect(Coordinator::Read::AgentChoiceImpact.count).to eq(1)
    expect(processed_events.count).to eq(4)
  end

  it "rolls back the invalidation claim until the accepted Choice projection is available" do
    invalidation = impact_events.last

    expect { projector.call(invalidation) }.to raise_error(
      Coordinator::Read::ProjectionStateError,
      "AgentChoiceAccepted must be projected before invalidation"
    )
    expect(processed_events).to be_empty

    create_accepted_choice
    projector.call(invalidation)
    expect(Coordinator::Read::Repositories::AgentChoices.new.fetch(choice_id)).to have_attributes(
      observation_status: "invalidated"
    )
  end

  def impact_events
    assessment = assessment_event
    accepted_link = source_link_event(
      role: "accepted_choice",
      source: accepted_choice_reference,
    )
    decision_link = source_link_event(
      role: "decision_change",
      source: decision_change.source_event,
    )
    invalidation = append_fixture(
      payload: Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV2.new(
        choice_id:,
        reason: "blocking_policy_introduced"
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice(choice_id),
      policy_version: "agent-choice-decision-impact/v1",
      metadata: Coordinator::Write::Metadata::AgentChoiceInvalidationV2.new(
        command_id: "cmd-impact-assessment",
        actor_kind: "system",
        actor_id: "agent-choice-decision-impact",
        recorded_by: "coordinator",
        policy_version: "agent-choice-decision-impact/v1",
        previous_context_digest: before_context_digest,
        resulting_context_digest: after_context_digest
      ),
      correlation_id:,
      caused_by: accepted_choice_event,
      markers: assessment_markers
    )
    [ assessment, accepted_link, decision_link, invalidation ]
  end

  def assessment_event
    @assessment_event ||= append_fixture(
      payload: Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1.new(
        assessment_id:,
        choice_id:,
        attempt_id:,
        assessment: impact_assessment
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice_impact(assessment_id),
      policy_version: "agent-choice-decision-impact/v1",
      metadata: Coordinator::Write::Metadata::AgentChoiceImpactAssessmentV2.new(
        command_id: "cmd-impact-assessment",
        actor_kind: "system",
        actor_id: "agent-choice-decision-impact",
        recorded_by: "coordinator",
        policy_version: "agent-choice-decision-impact/v1",
        before_context_digest:,
        after_context_digest:
      ),
      correlation_id:,
      caused_by: decision_source_event,
      markers: assessment_markers
    )
  end

  def source_link_event(role:, source:)
    append_fixture(
      payload: Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1.new(
        assessment_id:,
        role:,
        source:
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice_impact(assessment_id),
      command_id: "cmd-impact-assessment",
      actor_kind: "system",
      actor_id: "agent-choice-decision-impact",
      policy_version: "agent-choice-decision-impact/v1",
      correlation_id:,
      caused_by: assessment_event,
      markers: assessment_markers
    )
  end

  def impact_assessment
    @impact_assessment ||= Coordinator::Write::AgentChoiceImpacts::ImpactAssessmentV2.new(
      before_evaluation: policy_evaluation(
        status: "allowed",
        basis: "compliant",
        reason_code: "selected_option_satisfies_decision"
      ),
      after_evaluation: policy_evaluation(
        status: "blocked",
        basis: "blocking_violation",
        reason_code: "selected_option_violates_blocking_decision"
      ),
      outcome: "invalidated",
      reason: "blocking_policy_introduced"
    )
  end

  def policy_evaluation(status:, basis:, reason_code:)
    Coordinator::Write::AgentChoices::PolicyEvaluationV1.new(
      status:,
      effective_decision: nil,
      contributing_decisions: [],
      basis:,
      warnings: [],
      reason_codes: [ reason_code ]
    )
  end

  def create_accepted_choice
    create(
      :coordinator_read_agent_choice,
      :accepted,
      choice_id:,
      observation_status: "accepted",
      accepted_event: accepted_choice_reference.to_h.deep_stringify_keys,
      accepted_correlation_id: correlation_id
    )
  end

  def assessment_markers
    [ "impact-assessment:#{assessment_id}", "choice:#{choice_id}", "attempt:#{attempt_id}" ]
  end

  def before_context_digest
    "sha256:#{'a' * 64}"
  end

  def after_context_digest
    "sha256:#{'b' * 64}"
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def decision_source_event
    @decision_source_event ||= begin
      base = native_definition("rspec")
      recorded = append_fixture(
        payload: Coordinator::Write::Events::DecisionRecordedV2.new(
          decision_id: "D-impact-project", interpretation_id: "I-impact-base", source_message_id: "M-impact-base",
          definition: base.document
        ),
        stream: streams.decision("D-impact-project"), policy_version: "decision-governance/v1",
        actor_kind: "orchestrator", actor_id: "guidance-host"
      )
      activated = append_fixture(
        payload: Coordinator::Write::Events::DecisionActivatedV2.new(
          decision_id: "D-impact-project", interpretation_id: "I-impact-base", rationale: "Activate the accepted policy."
        ),
        stream: streams.decision("D-impact-project"), policy_version: "decision-governance/v1",
        actor_kind: "orchestrator", actor_id: "guidance-host", caused_by: recorded
      )
      append_fixture(
        payload: Coordinator::Write::Events::DecisionDefinitionCorrectedV2.new(
          decision_id: "D-impact-project", interpretation_id: "I-impact-next", source_message_id: "M-impact-next",
          definition: native_definition("minitest").document, rationale: "Apply the accepted correction."
        ),
        stream: streams.decision("D-impact-project"), policy_version: "decision-governance/v1",
        command_id: "cmd-decision-change", actor_kind: "orchestrator", actor_id: "guidance-host", caused_by: activated
      )
    end
  end

  def native_definition(option_id)
    input = InterpretationInput.build(
      value: InterpretationInput.named_choice(option_id),
      scope: InterpretationInput.scope(repository_ids: [], attempt_id:),
      enforcement: { level: "merge_gate", retroactivity: "active_attempts", on_violation: "block" }
    )
    proposal = Coordinator::Write::Events::DecisionInterpretationProposedV2.new(
      interpretation_id: "I-impact-definition", source_message_id: "M-impact-definition", source_span: "RSpec",
      proposed_decision: input.fetch(:proposed_decision), assessment: "accepted_for_activation", ambiguities: []
    )
    Coordinator::Write::Decisions::DecisionDefinitionBuilder.new.call(
      proposal:, valid_from_default: "2026-08-30T12:00:00.000000Z"
    )
  end

  def decision_change
    Coordinator::Read::AgentChoiceImpacts::DecisionChangeLoader.new(event_store:)
      .call(event_reference(decision_source_event)).evidence
  end

  def accepted_choice_event
    @accepted_choice_event ||= begin
      attributes = attributes_for(:coordinator_read_agent_choice, choice_id:).deep_symbolize_keys
      recorded = append_fixture(
        payload: Coordinator::Write::Events::AgentChoiceRecordedV2.new(
          choice_id:, choice_type: attributes.fetch(:choice_type), selected: attributes.fetch(:selected),
          alternatives: attributes.fetch(:alternatives), reason_summary: attributes.fetch(:reason_summary),
          context: attributes.fetch(:context),
          decision_context: { document: attributes.fetch(:decision_context).fetch(:document) }
        ),
        stream: streams.agent_choice(choice_id), policy_version: "testing-framework-resolution/v1"
      )
      append_fixture(
        payload: Coordinator::Write::Events::AgentChoiceAcceptedV2.new(
          choice_id:, assessment: { basis: "no_policy", based_on_decisions: [], warnings: [] }
        ),
        stream: streams.agent_choice(choice_id), policy_version: "testing-framework-resolution/v1",
        caused_by: recorded
      )
    end
  end

  def accepted_choice_reference
    event_reference(accepted_choice_event)
  end

  def append_fixture(payload:, stream:, policy_version:, metadata: nil, command_id: "cmd-impact-fixture",
                     actor_kind: "agent", actor_id: "fixture-agent", caused_by: nil, markers: [], correlation_id: self.correlation_id)
    event = Coordinator::Write::EventFactory.new.build!(
      event: payload, event_id: SecureRandom.uuid_v7,
      metadata: metadata || Coordinator::Write::EventMetadata.new(
        command_id:, actor_kind:, actor_id:, recorded_by: "coordinator", policy_version:
      ),
      markers:, caused_by:, correlation_id:
    )
    event_store.append(stream, [ event ]).sole
  end

  def impact_repository
    @impact_repository ||= Coordinator::Read::Repositories::AgentChoiceImpacts.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "agent_choice_impacts",
      projection_version: 1
    )
  end
end

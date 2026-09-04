# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoiceImpactsV1, :read_model do
  subject(:projector) { described_class.new(assessment_loader:) }

  let(:choice_id) { "CHO-impact-project" }
  let(:attempt_id) { "A-impact-project" }
  let(:assessment_id) { SecureRandom.uuid_v7 }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:decision_changed_at) { "2026-08-30T11:59:00.000000Z" }
  let(:assessment_loader) do
    assessment = assessment_view
    Class.new do
      define_method(:initialize) { |view| @view = view }
      define_method(:call) { |identifier| @view if identifier == @view.assessment_id }
    end.new(assessment)
  end

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
      revision: 1,
      global_position: 201
    )
    decision_link = source_link_event(
      role: "decision_change",
      source: decision_change.source_event,
      revision: 2,
      global_position: 202
    )
    invalidation = ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV2.new(
        choice_id:,
        reason: "blocking_policy_introduced"
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice(choice_id),
      stream_revision: 2,
      global_position: 203,
      command_id: "cmd-impact-assessment",
      actor_kind: "system",
      actor_id: "agent-choice-decision-impact",
      policy_version: "agent-choice-decision-impact/v1",
      correlation_id:,
      causation_id: assessment.id,
      markers: assessment_markers
    )
    [ assessment, accepted_link, decision_link, invalidation ]
  end

  def assessment_event
    @assessment_event ||= ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::AgentChoiceImpactAssessmentRecordedV1.new(
        assessment_id:,
        choice_id:,
        attempt_id:,
        assessment: impact_assessment
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice_impact(assessment_id),
      stream_revision: 0,
      global_position: 200,
      command_id: "cmd-impact-assessment",
      actor_kind: "system",
      actor_id: "agent-choice-decision-impact",
      policy_version: "agent-choice-decision-impact/v1",
      correlation_id:,
      causation_id: SecureRandom.uuid_v7,
      markers: assessment_markers
    )
  end

  def source_link_event(role:, source:, revision:, global_position:)
    ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::AgentChoiceImpactSourceLinkedV1.new(
        assessment_id:,
        role:,
        source:
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice_impact(assessment_id),
      stream_revision: revision,
      global_position:,
      command_id: "cmd-impact-assessment",
      actor_kind: "system",
      actor_id: "agent-choice-decision-impact",
      policy_version: "agent-choice-decision-impact/v1",
      correlation_id:,
      causation_id: assessment_event.id,
      markers: assessment_markers
    )
  end

  def assessment_view
    Coordinator::Read::AgentChoiceImpacts::AssessmentViewV2.new(
      assessment_id:,
      choice_id:,
      attempt_id:,
      assessment: impact_assessment,
      accepted_choice: accepted_choice_reference,
      decision_change:,
      decision_changed_at:,
      assessment_event:
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

  def decision_change
    @decision_change ||= Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2.new(
      source_event: source_reference("DecisionDefinitionCorrected", "Decision", "D-impact-project", 2),
      source_global_position: 100,
      source_command_id: "cmd-decision-change",
      source_actor: Coordinator::Write::Commands::Actor.new(kind: "orchestrator", id: "guidance-host"),
      decision_id: "D-impact-project",
      change_kind: "corrected",
      definition_digest: "sha256:#{'c' * 64}",
      retroactivity: "active_attempts",
      affected_partitions: [
        Coordinator::Write::Decisions::DecisionPartitionV1.new(
          partition_id: "attempt:#{attempt_id}:testing",
          topic_root: "testing",
          anchor_kind: "attempt",
          anchor_id: attempt_id
        )
      ]
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

  def accepted_choice_reference
    @accepted_choice_reference ||= source_reference("AgentChoiceAccepted", "AgentChoice", choice_id, 1)
  end

  def assessment_markers
    [ "impact-assessment:#{assessment_id}", "choice:#{choice_id}", "attempt:#{attempt_id}" ]
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: type.start_with?("AgentChoice") ? "AgentGovernance" : "HumanGuidance",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
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

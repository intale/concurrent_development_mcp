# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoiceImpactsV1, :read_model do
  subject(:projector) { described_class.new }

  let(:choice_id) { "CHO-impact-project" }
  let(:attempt_id) { "A-impact-project" }
  let(:assessment_id) { "ACI-impact-project" }
  let(:correlation_id) { SecureRandom.uuid_v7 }

  it "projects assessment and invalidation evidence idempotently with exact attribution" do
    create_accepted_choice
    assessment, invalidation = impact_events

    projector.call(assessment)
    projector.call(assessment)
    projector.call(invalidation)
    projector.call(invalidation)

    page = impact_repository.page(
      Coordinator::Read::AgentChoiceImpactListQueryV1.new(
        attempt_id:,
        after_global_position: nil,
        limit: 20
      )
    )
    impact = page.items.sole
    expect(impact).to have_attributes(
      outcome: "invalidated",
      reason: "blocking_policy_introduced",
      accepted_choice: accepted_choice_reference,
      source_actor: have_attributes(kind: "orchestrator", id: "guidance-host"),
      assessment_evidence: have_attributes(
        event: event_reference(assessment),
        actor: have_attributes(kind: "system", id: "agent-choice-decision-impact"),
        global_position: assessment.global_position,
        causation_id: assessment.causation_id,
        correlation_id: assessment.correlation_id
      )
    )
    expect(impact.decision_change.source_actor).to have_attributes(
      kind: "orchestrator",
      id: "guidance-host"
    )

    choice = Coordinator::Read::Repositories::AgentChoices.new.fetch(choice_id)
    expect(choice).to have_attributes(
      observation_status: "invalidated",
      invalidation: have_attributes(
        reason: "blocking_policy_introduced",
        assessment_event: event_reference(assessment),
        evidence: have_attributes(
          event: event_reference(invalidation),
          causation_id: invalidation.causation_id,
          correlation_id: invalidation.correlation_id
        )
      )
    )
    expect(Coordinator::Read::AgentChoiceImpact.count).to eq(1)
    expect(processed_events.count).to eq(2)
  end

  it "rolls back the idempotency claim until the accepted Choice projection is available" do
    _assessment, invalidation = impact_events

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
    assessment = ProjectionEventFactory.build(
      payload: assessment_payload,
      stream: Coordinator::Write::StreamFactory.new.agent_choice_impact(assessment_id),
      stream_revision: 0,
      global_position: 200,
      command_id: "cmd-impact-assessment",
      actor_kind: "system",
      actor_id: "agent-choice-decision-impact",
      policy_version: "agent-choice-decision-impact/v1",
      correlation_id:,
      causation_id: SecureRandom.uuid_v7,
      markers: [ "choice:#{choice_id}", "attempt:#{attempt_id}" ]
    )
    invalidation = ProjectionEventFactory.build(
      payload: Coordinator::Write::Events::AgentChoiceInvalidatedByDecisionV1.new(
        choice_id:,
        accepted_choice: accepted_choice_reference,
        assessment_event: event_reference(assessment),
        decision_change_event: decision_change.source_event,
        previous_context_digest: "sha256:#{'a' * 64}",
        resulting_context_digest: "sha256:#{'b' * 64}",
        reason: "blocking_policy_introduced",
        invalidated_at: "2026-08-30T12:02:00.000000Z"
      ),
      stream: Coordinator::Write::StreamFactory.new.agent_choice(choice_id),
      stream_revision: 2,
      global_position: 300,
      command_id: "cmd-impact-invalidation",
      actor_kind: "system",
      actor_id: "agent-choice-decision-impact",
      policy_version: "agent-choice-decision-impact/v1",
      correlation_id:,
      causation_id: assessment.id,
      markers: [ "choice:#{choice_id}", "attempt:#{attempt_id}" ]
    )
    [ assessment, invalidation ]
  end

  def assessment_payload
    Coordinator::Write::Events::AgentChoiceImpactAssessedV1.new(
      assessment_id:,
      choice_id:,
      attempt_id:,
      accepted_choice: accepted_choice_reference,
      decision_change:,
      assessment: Coordinator::Write::AgentChoiceImpacts::AssessmentV1.new(
        policy_version: "agent-choice-decision-impact/v1",
        before_context_digest: "sha256:#{'a' * 64}",
        after_context_digest: "sha256:#{'b' * 64}",
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
        source_advancements: [ partition_advancement_reference ],
        outcome: "invalidated",
        reason: "blocking_policy_introduced"
      ),
      assessed_at: "2026-08-30T12:01:00.000000Z"
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
    @decision_change ||= Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1.new(
      source_event: source_reference(
        "DecisionDefinitionCorrected",
        "Decision",
        "D-impact-project",
        2
      ),
      source_global_position: 100,
      source_command_id: "cmd-decision-change",
      source_actor: Coordinator::Write::Commands::Actor.new(
        kind: "orchestrator",
        id: "guidance-host"
      ),
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
      ],
      changed_at: "2026-08-30T12:00:00.000000Z"
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
    @accepted_choice_reference ||= source_reference(
      "AgentChoiceAccepted",
      "AgentChoice",
      choice_id,
      1
    )
  end

  def partition_advancement_reference
    @partition_advancement_reference ||= source_reference(
      "DecisionPartitionAdvanced",
      "DecisionPartition",
      "attempt:#{attempt_id}:testing",
      1
    )
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

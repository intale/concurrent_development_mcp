# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::AgentChoiceImpactsV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  let(:choice_projector) { Coordinator::Read::Projectors::AgentChoicesV1.new }

  it "projects assessment and invalidation evidence idempotently with exact attribution" do
    scenario = impact_scenario("impact-project")
    recorded, accepted, invalidation = scenario.fetch(:choice_events)
    assessment = scenario.fetch(:assessment)
    choice_projector.call(recorded)
    choice_projector.call(accepted)

    projector.call(assessment)
    projector.call(assessment)
    projector.call(invalidation)
    projector.call(invalidation)

    page = impact_repository.page(
      Coordinator::Read::AgentChoiceImpactListQueryV1.new(
        attempt_id: scenario.fetch(:choice).fetch(:identifiers).fetch(:attempt_id),
        after_global_position: nil,
        limit: 20
      )
    )
    impact = page.items.sole
    expect(impact).to have_attributes(
      outcome: "invalidated",
      reason: "blocking_policy_introduced",
      accepted_choice: AgentChoiceImpactScenario.reference(accepted),
      source_actor: have_attributes(kind: "orchestrator", id: "guidance-host"),
      assessment_evidence: have_attributes(
        event: AgentChoiceImpactScenario.reference(assessment),
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

    choice = Coordinator::Read::Repositories::AgentChoices.new.fetch(recorded.stream.stream_id)
    expect(choice).to have_attributes(
      observation_status: "invalidated",
      invalidation: have_attributes(
        reason: "blocking_policy_introduced",
        assessment_event: AgentChoiceImpactScenario.reference(assessment),
        evidence: have_attributes(
          event: AgentChoiceImpactScenario.reference(invalidation),
          causation_id: invalidation.causation_id,
          correlation_id: invalidation.correlation_id
        )
      )
    )
    expect(Coordinator::Read::AgentChoiceImpact.count).to eq(1)
    expect(processed_events.count).to eq(2)
  end

  it "rolls back the idempotency claim until the accepted Choice projection is available" do
    scenario = impact_scenario("impact-project-order")
    recorded, accepted, invalidation = scenario.fetch(:choice_events)

    expect { projector.call(invalidation) }.to raise_error(
      Coordinator::Read::ProjectionStateError,
      "AgentChoiceAccepted must be projected before invalidation"
    )
    expect(processed_events).to be_empty

    choice_projector.call(recorded)
    choice_projector.call(accepted)
    projector.call(invalidation)
    expect(Coordinator::Read::Repositories::AgentChoices.new.fetch(recorded.stream.stream_id)).to have_attributes(
      observation_status: "invalidated"
    )
  end

  def impact_scenario(prefix)
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix:)
    decision_id = "D-#{prefix}"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "#{prefix}-base",
      decision_id:,
      option_id: "rspec",
      scope: InterpretationInput.scope(repository_ids: [ "billing" ])
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "#{prefix}-change",
      decision_id:,
      option_id: "minitest",
      scope: InterpretationInput.scope(repository_ids: [ "billing" ])
    )
    parent = AgentChoiceImpactScenario.start_scan(source)
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:, caused_by: parent)
    assessment = Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(
      event_store: AgentChoiceImpactScenario.event_store
    ).call(invocation).value!
    {
      choice:,
      source:,
      assessment:,
      choice_events: AgentChoiceImpactScenario.choice_events(choice.fetch(:identifiers).fetch(:choice_id))
    }
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

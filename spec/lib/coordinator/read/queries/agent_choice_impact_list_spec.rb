# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::AgentChoiceImpactList, :event_store, :read_model do
  subject(:query) { described_class.new }

  let(:choice_query) { Coordinator::Read::Queries::AgentChoiceGet.new }
  let(:choice_projector) { Coordinator::Read::Projectors::AgentChoicesV1.new }
  let(:impact_projector) { Coordinator::Read::Projectors::AgentChoiceImpactsV1.new }

  it "serves every available stage while assessment and invalidation projections lag independently" do
    scenario = impact_scenarios(prefix: "impact-query-lag", count: 1).sole
    recorded, accepted, invalidation = scenario.fetch(:choice_events)
    choice_projector.call(recorded)
    choice_projector.call(accepted)

    empty = query.call(attempt_id: scenario.fetch(:attempt_id)).value!.data.page
    expect(empty).to have_attributes(items: [], next_global_position: nil, has_more: false)
    expect(choice_query.call(choice_id: scenario.fetch(:choice_id)).value!.data.choice).to have_attributes(
      observation_status: "accepted",
      invalidation: nil
    )

    impact_projector.call(scenario.fetch(:assessment))
    available = query.call(attempt_id: scenario.fetch(:attempt_id)).value!.data.page
    expect(available.items.sole).to have_attributes(
      choice_id: scenario.fetch(:choice_id),
      outcome: "invalidated"
    )
    expect(choice_query.call(choice_id: scenario.fetch(:choice_id)).value!.data.choice.observation_status).to eq(
      "accepted"
    )

    impact_projector.call(invalidation)
    invalidated = choice_query.call(choice_id: scenario.fetch(:choice_id)).value!
    expect(invalidated.data.choice).to have_attributes(
      observation_status: "invalidated",
      invalidation: be_a(Coordinator::Read::AgentChoiceInvalidationViewV1)
    )
    expect(invalidated.next_actions.sole).to have_attributes(
      tool: "decision_resolve",
      arguments: have_attributes(
        topic_id: "testing.framework",
        context: invalidated.data.choice.context
      )
    )
    expect(invalidated.data.choice.to_h.keys & %i[fresh pending projection_status]).to be_empty
  end

  it "pages assessments by opaque global-position cursor with strict limits" do
    scenarios = impact_scenarios(prefix: "impact-query-page", count: 3)
    scenarios.each { impact_projector.call(_1.fetch(:assessment)) }
    attempt_id = scenarios.first.fetch(:attempt_id)

    first = query.call(attempt_id:, limit: 2).value!.data.page
    expect(first).to have_attributes(has_more: true)
    expect(first.items.map(&:choice_id)).to eq(scenarios.first(2).map { _1.fetch(:choice_id) })
    expect(first.next_global_position).to eq(first.items.last.assessment_evidence.global_position)

    second = query.call(
      attempt_id:,
      after_global_position: first.next_global_position,
      limit: 2
    ).value!.data.page
    expect(second).to have_attributes(
      items: contain_exactly(have_attributes(choice_id: scenarios.last.fetch(:choice_id))),
      next_global_position: nil,
      has_more: false
    )
    expect(first.items.first.source_actor).to have_attributes(
      kind: "orchestrator",
      id: "guidance-host"
    )
  end

  it "returns typed invalid input without consulting pg_eventstore" do
    result = query.call(attempt_id: "bad id", limit: 101).value!

    expect(result).to have_attributes(status: "invalid")
    expect(result.data).to have_attributes(code: "invalid_input")
  end

  def impact_scenarios(prefix:, count:)
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix:)
    decision_id = "D-#{prefix}"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "#{prefix}-base",
      decision_id:,
      option_id: "rspec",
      scope: InterpretationInput.scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ])
    )
    choices = Array.new(count) do |index|
      AgentChoiceImpactScenario.record_choice(
        prepared:,
        option_id: "rspec",
        choice_id: "CHO-#{prefix}-#{index}"
      )
    end
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "#{prefix}-change",
      decision_id:,
      option_id: "minitest",
      scope: InterpretationInput.scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ])
    )
    parent = AgentChoiceImpactScenario.start_scan(source)

    choices.map do |choice|
      invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:, caused_by: parent)
      assessment = Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(
        event_store: AgentChoiceImpactScenario.event_store
      ).call(invocation).value!
      {
        choice:,
        choice_id: choice.fetch(:identifiers).fetch(:choice_id),
        attempt_id: choice.fetch(:identifiers).fetch(:attempt_id),
        assessment:,
        choice_events: AgentChoiceImpactScenario.choice_events(choice.fetch(:identifiers).fetch(:choice_id))
      }
    end
  end
end

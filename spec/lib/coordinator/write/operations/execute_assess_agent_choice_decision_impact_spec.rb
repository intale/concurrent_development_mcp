# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }

  it "CHO-02-ASSESS-INVALIDATE-01 reconstructs exact history, invalidates atomically, and replays" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-invalidate")
    scope = repository_scope("billing")
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-invalidate-base",
      decision_id: "D-impact-invalidate",
      option_id: "rspec",
      scope:
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-invalidate-next",
      decision_id: "D-impact-invalidate",
      option_id: "minitest",
      scope: InterpretationInput.scope(
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        work_item_id: prepared.fetch(:identifiers).fetch(:work_item_id)
      )
    )
    parent = AgentChoiceImpactScenario.start_scan(source)
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:, caused_by: parent)

    original = operation.call(invocation)
    replay = operation.call(invocation)

    expect(original).to be_success
    expect(replay).to be_success
    expect(replay.value!.id).to eq(original.value!.id)
    assessment_event = original.value!
    assessment = load(assessment_event)
    expect(assessment.assessment).to have_attributes(
      outcome: "invalidated",
      reason: "blocking_policy_introduced",
      before_evaluation: have_attributes(status: "allowed", basis: "compliant"),
      after_evaluation: have_attributes(status: "blocked", basis: "blocking_violation")
    )
    assessment_history = AgentChoiceImpactScenario.assessment_history(invocation.command.assessment_id)
    expect(assessment_history.map(&:type)).to eq(
      %w[AgentChoiceImpactAssessmentRecorded AgentChoiceImpactSourceLinked AgentChoiceImpactSourceLinked]
    )
    links = assessment_history.drop(1).map { load(_1) }
    expect(links.map(&:role)).to contain_exactly("accepted_choice", "decision_change")
    expect(links.find { _1.role == "accepted_choice" }.source).to eq(
      AgentChoiceImpactScenario.reference(choice.fetch(:accepted))
    )
    expect(links.find { _1.role == "decision_change" }.source).to eq(
      AgentChoiceImpactScenario.reference(source)
    )
    events = AgentChoiceImpactScenario.choice_events(choice_id(choice))
    expect(events.map(&:type)).to eq(
      %w[AgentChoiceRecorded AgentChoiceAccepted AgentChoiceInvalidatedByDecision]
    )
    invalidation_event = events.last
    invalidation = load(invalidation_event)
    expect(invalidation).to have_attributes(
      choice_id: choice_id(choice),
      reason: "blocking_policy_introduced"
    )
    expect([ assessment_event, invalidation_event ]).to all(
      have_attributes(
        causation_id: invocation.caused_by.id,
        correlation_id: parent.correlation_id
      )
    )
    expect(invocation.caused_by).to have_attributes(
      type: "ProcessStepPlanned",
      causation_id: parent.id,
      correlation_id: parent.correlation_id
    )
    expect(assessment_event.markers).to include(
      "impact-assessment:#{invocation.command.assessment_id}",
      "choice:#{choice_id(choice)}",
      "attempt:#{choice.fetch(:identifiers).fetch(:attempt_id)}",
      "decision:D-impact-invalidate",
      "decision-change:#{source.id}"
    )
    expect(invalidation_event.markers).to include(
      "decision-partition:repo:#{RepositoryScenario::DEFAULT_REPOSITORY_ID}:testing",
      "decision-partition:attempt:#{choice.fetch(:identifiers).fetch(:attempt_id)}:testing"
    )
    expect(AgentChoiceImpactScenario.assessment_events(invocation.command.assessment_id).length).to eq(1)
  end

  it "CHO-02-ASSESS-STILL-VALID-01 records an explicit one-stream assessment" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-valid")
    scope = repository_scope("billing")
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-valid-base",
      decision_id: "D-impact-valid",
      option_id: "rspec",
      scope:
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-valid-next",
      decision_id: "D-impact-valid",
      option_id: "rspec",
      scope:,
      enforcement: AgentChoiceImpactScenario.advisory_enforcement
    )
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:)

    result = operation.call(invocation)

    expect(result).to be_success
    expect(load(result.value!).assessment).to have_attributes(
      outcome: "still_valid",
      reason: "compliant_or_advisory",
      before_evaluation: have_attributes(status: "allowed"),
      after_evaluation: have_attributes(status: "allowed")
    )
    expect(AgentChoiceImpactScenario.choice_events(choice_id(choice)).map(&:type)).to eq(
      %w[AgentChoiceRecorded AgentChoiceAccepted]
    )
  end

  it "CHO-02-ASSESS-NOT-APPLICABLE-01 records a change already observed by the Choice" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-observed")
    scope = repository_scope("billing")
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-observed-base",
      decision_id: "D-impact-observed",
      option_id: "rspec",
      scope:
    )
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-observed-next",
      decision_id: "D-impact-observed",
      option_id: "minitest",
      scope:
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "minitest")
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:)

    result = operation.call(invocation)

    expect(result).to be_success
    expect(load(result.value!).assessment).to have_attributes(
      outcome: "not_applicable",
      reason: "change_already_observed"
    )
    expect(AgentChoiceImpactScenario.choice_events(choice_id(choice)).length).to eq(2)
  end

  it "CHO-02-ASSESS-ALREADY-INVALID-01 records later impact without reopening the Choice" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-terminal")
    scope = repository_scope("billing")
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-terminal-base",
      decision_id: "D-impact-terminal",
      option_id: "rspec",
      scope:
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    first_source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-terminal-first",
      decision_id: "D-impact-terminal",
      option_id: "minitest",
      scope:
    )
    operation.call(
      AgentChoiceImpactScenario.assessment_invocation(choice:, source: first_source)
    ).value!
    second_source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-terminal-second",
      decision_id: "D-impact-terminal",
      option_id: "test-unit",
      scope:
    )
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source: second_source)

    result = operation.call(invocation)

    expect(result).to be_success
    expect(load(result.value!).assessment).to have_attributes(
      outcome: "already_invalidated",
      reason: "choice_terminal"
    )
    expect(AgentChoiceImpactScenario.choice_events(choice_id(choice)).map(&:type)).to eq(
      %w[AgentChoiceRecorded AgentChoiceAccepted AgentChoiceInvalidatedByDecision]
    )
  end

  it "leaves a mismatched target/source pair as operator-visible poison" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-poison")
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-poison-source",
      decision_id: "D-impact-poison",
      option_id: "minitest",
      scope: repository_scope("orders")
    )
    invocation = AgentChoiceImpactScenario.assessment_invocation(choice:, source:)

    expect { operation.call(invocation) }.to raise_error(
      Coordinator::Write::AgentChoiceImpacts::InvalidHistory,
      /no_affected_choice_partitions/
    )
    expect(AgentChoiceImpactScenario.assessment_events(invocation.command.assessment_id)).to be_empty
    expect(AgentChoiceImpactScenario.choice_events(choice_id(choice)).length).to eq(2)
  end

  it "leaves a malformed exact Decision source reference as operator-visible poison" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-source-poison")
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-source-poison-source",
      decision_id: "D-impact-source-poison",
      option_id: "minitest",
      scope: repository_scope("billing")
    )
    valid = AgentChoiceImpactScenario.assessment_invocation(choice:, source:)
    malformed_reference = Coordinator::Write::EventReference.new(
      valid.command.decision_change.source_event.to_h.merge(
        event_id: "0198e03a-d112-7000-8000-000000000099"
      )
    )
    malformed_change = Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1.new(
      valid.command.decision_change.to_h.merge(source_event: malformed_reference.to_h)
    )
    command = Coordinator::Write::Commands::AssessAgentChoiceDecisionImpact.new(
      command_id: valid.command.command_id,
      actor: valid.command.actor,
      assessment_id: valid.command.assessment_id,
      choice_id: valid.command.choice_id,
      accepted_choice: valid.command.accepted_choice,
      decision_change: malformed_change,
      policy_version: valid.command.policy_version
    )
    invocation = Coordinator::Write::AgentChoiceImpactAssessmentInvocation.new(
      command:,
      caused_by: valid.caused_by,
      caused_by_reference: valid.caused_by_reference
    )

    expect { operation.call(invocation) }.to raise_error(
      Coordinator::Write::AgentChoiceImpacts::InvalidHistory,
      /decision_change_source_missing/
    )
    expect(AgentChoiceImpactScenario.assessment_events(valid.command.assessment_id)).to be_empty
    expect(AgentChoiceImpactScenario.choice_events(choice_id(choice)).length).to eq(2)
  end

  it "CHO-02-ASSESS-RACE-01 serializes two independent invalidating Decision changes" do
    prime_agent_choice_impact_partitions
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-race")
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    repository_source = AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-race-repository",
      decision_id: "D-impact-race-repository",
      option_id: "minitest",
      scope: repository_scope("billing")
    )
    identifiers = choice.fetch(:identifiers)
    attempt_source = AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-race-attempt",
      decision_id: "D-impact-race-attempt",
      option_id: "minitest",
      scope: InterpretationInput.scope(
        repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ],
        change_set_id: identifiers.fetch(:change_set_id),
        work_item_id: identifiers.fetch(:work_item_id),
        attempt_id: identifiers.fetch(:attempt_id)
      )
    )
    invocations = [ repository_source, attempt_source ].map do |source|
      AgentChoiceImpactScenario.assessment_invocation(choice:, source:)
    end

    results = invocations.map do |invocation|
      Thread.new do
        described_class.new(
          event_store: Coordinator::Write::EventStore.new(client: PgEventstore.client)
        ).call(invocation)
      end
    end.map(&:value)

    expect(results).to all(be_success)
    outcomes = results.map { load(_1.value!).assessment.outcome }
    expect(outcomes).to contain_exactly("invalidated", "already_invalidated")
    choice_history = AgentChoiceImpactScenario.choice_events(choice_id(choice))
    expect(choice_history.map(&:type)).to eq(
      %w[AgentChoiceRecorded AgentChoiceAccepted AgentChoiceInvalidatedByDecision]
    )
    expect(invocations.sum { AgentChoiceImpactScenario.assessment_events(_1.command.assessment_id).length }).to eq(2)
  end

  def operation
    described_class.new(event_store:)
  end

  def prime_agent_choice_impact_partitions
    repository_key = "impact-race-partition-prime"
    prepared = AgentChoiceImpactScenario.prepare_attempt(
      prefix: "impact-race-partition-prime",
      repository_id: repository_key
    )
    scope = repository_scope(repository_key)
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-race-partition-prime-base",
      decision_id: "D-impact-race-partition-prime",
      option_id: "rspec",
      scope:
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-race-partition-prime-change",
      decision_id: "D-impact-race-partition-prime",
      option_id: "minitest",
      scope:
    )

    operation.call(
      AgentChoiceImpactScenario.assessment_invocation(choice:, source:)
    ).value!
  end

  def repository_scope(repository_id)
    InterpretationInput.scope(repository_ids: [ RepositoryScenario.repository_id(repository_id) ])
  end

  def choice_id(choice)
    choice.fetch(:identifiers).fetch(:choice_id)
  end

  def load(event)
    AgentChoiceImpactScenario.load(event)
  end
end

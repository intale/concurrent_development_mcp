# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::AgentChoiceDecisionImpact, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  subject(:process_manager) { described_class.new(event_store:) }

  it "runs the lifecycle-to-page Saga with exact replay, tracing, and terminal invalidation" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-process-direct")
    decision_id = "D-impact-process-direct"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-process-direct-base",
      decision_id:,
      option_id: "rspec",
      scope: repository_scope
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-process-direct-change",
      decision_id:,
      option_id: "minitest",
      scope: repository_scope
    )

    expect(process_manager.call(source)).to be_nil
    started = scan_event(source, "AgentChoiceImpactScanStarted")
    expect(process_manager.call(started)).to be_nil
    expect(process_manager.call(source)).to be_nil
    expect(process_manager.call(started)).to be_nil

    assessment = assessment_events(choice, source).sole
    invalidation = choice_events(choice).find { _1.type == "AgentChoiceInvalidatedByDecision" }
    completed = scan_event(source, "AgentChoiceImpactScanCompleted")
    expect(load(assessment).assessment).to have_attributes(
      outcome: "invalidated",
      reason: "blocking_policy_introduced"
    )
    expect(scan_events(source).map(&:type)).to contain_exactly(
      "AgentChoiceImpactScanStarted",
      "AgentChoiceImpactScanCompleted"
    )
    expect(choice_events(choice).map(&:type)).to eq(
      [ "AgentChoiceRecorded", "AgentChoiceAccepted", "AgentChoiceInvalidatedByDecision" ]
    )
    expect(started.causation_id).to eq(source.id)
    expect([ assessment, invalidation, completed ].map(&:causation_id).uniq).to eq([ started.id ])
    expect([ source, started, assessment, invalidation, completed ].map(&:correlation_id).uniq).to eq(
      [ source.correlation_id ]
    )
  end

  it "repairs a late accepted Choice from current write-side partition and Decision heads" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-process-repair")
    decision_id = "D-impact-process-repair"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-process-repair-base",
      decision_id:,
      option_id: "rspec",
      scope: repository_scope
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-process-repair-change",
      decision_id:,
      option_id: "minitest",
      scope: repository_scope
    )

    expect(process_manager.call(choice.fetch(:accepted))).to be_nil
    expect(process_manager.call(choice.fetch(:accepted))).to be_nil

    assessment = assessment_events(choice, source).sole
    payload = load(assessment)
    expect(payload.decision_change.source_event).to eq(reference(source))
    expect(payload.assessment.outcome).to eq("invalidated")
    expect(assessment.causation_id).to eq(choice.fetch(:accepted).id)
    expect(assessment.correlation_id).to eq(choice.fetch(:accepted).correlation_id)
    expect(scan_events(source)).to be_empty
    expect(choice_events(choice).count { _1.type == "AgentChoiceInvalidatedByDecision" }).to eq(1)
  end

  it "finds the latest correction after a Decision moves outside every recorded Choice partition" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-process-moved-repair")
    decision_id = "D-impact-process-moved-repair"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-process-moved-repair-base",
      decision_id:,
      option_id: "rspec",
      scope: repository_scope
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-process-moved-repair-change",
      decision_id:,
      option_id: "minitest",
      scope: InterpretationInput.scope(work_item_id: "W-outside-choice-context")
    )

    process_manager.call(choice.fetch(:accepted))

    payload = load(assessment_events(choice, source).sole)
    expect(payload.decision_change.source_event).to eq(reference(source))
    expect(payload.assessment).to have_attributes(
      outcome: "still_valid",
      reason: "compliant_or_advisory"
    )
    expect(choice_events(choice).none? { _1.type == "AgentChoiceInvalidatedByDecision" }).to be(true)
  end

  it "does not repair active Choices for a future-only divergent Decision head" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-process-future-repair")
    decision_id = "D-impact-process-future-repair"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-process-future-repair-base",
      decision_id:,
      option_id: "rspec",
      scope: repository_scope
    )
    choice = AgentChoiceImpactScenario.record_choice(prepared:, option_id: "rspec")
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-process-future-repair-change",
      decision_id:,
      option_id: "minitest",
      scope: repository_scope,
      enforcement: {
        level: "implementation_gate",
        retroactivity: "future_only",
        on_violation: "block"
      }
    )

    process_manager.call(choice.fetch(:accepted))

    expect(assessment_events(choice, source)).to be_empty
    expect(choice_events(choice).none? { _1.type == "AgentChoiceInvalidatedByDecision" }).to be(true)
  end

  it "redrives a partially assessed page and completes two pages for 51 exact targets" do
    prepared = AgentChoiceImpactScenario.prepare_attempt(prefix: "impact-process-pages")
    decision_id = "D-impact-process-pages"
    AgentChoiceImpactScenario.activate_decision(
      suffix: "impact-process-pages-base",
      decision_id:,
      option_id: "rspec",
      scope: repository_scope
    )
    choices = Array.new(51) do |index|
      AgentChoiceImpactScenario.record_choice(
        prepared:,
        option_id: "rspec",
        choice_id: "CHO-impact-process-page-#{index.to_s.rjust(2, '0')}"
      )
    end
    source = AgentChoiceImpactScenario.correct_decision(
      suffix: "impact-process-pages-change",
      decision_id:,
      option_id: "minitest",
      scope: repository_scope
    )
    process_manager.call(source)
    started = scan_event(source, "AgentChoiceImpactScanStarted")

    choices.first(20).each do |choice|
      result = Coordinator::Write::Operations::ExecuteAssessAgentChoiceDecisionImpact.new(event_store:).call(
        AgentChoiceImpactScenario.assessment_invocation(choice:, source:, caused_by: started)
      )
      expect(result).to be_success
    end

    process_manager.call(started)
    progressed = scan_event(source, "AgentChoiceImpactScanProgressed")
    progressed_payload = load(progressed)
    expect(progressed_payload).to have_attributes(
      page_number: 1,
      page_choice_count: 50,
      total_choice_count: 50
    )
    expect(process_manager.call(started)).to be_nil
    expect(choices.first(50).flat_map { assessment_events(_1, source) }.length).to eq(50)

    process_manager.call(progressed)
    expect(process_manager.call(progressed)).to be_nil
    completed = load(scan_event(source, "AgentChoiceImpactScanCompleted"))
    expect(completed).to have_attributes(
      page_count: 2,
      page_choice_count: 1,
      total_choice_count: 51
    )
    expect(choices.flat_map { assessment_events(_1, source) }.length).to eq(51)
    expect(choices.sum { choice_events(_1).count { |event| event.type == "AgentChoiceInvalidatedByDecision" } }).to eq(51)
  end

  it "publishes one unique multi-stream filter in the shared process-manager set" do
    definition = Coordinator::Processes::Subscriptions::AgentChoiceDecisionImpact::DEFINITION

    expect(definition.identity.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "agent-choice-decision-impact-v1"
    )
    expect(definition.options).to eq(
      filter: {
        streams: [
          { context: "HumanGuidance", stream_name: "Decision" },
          { context: "AgentGovernance", stream_name: "AgentChoice" },
          { context: "AgentGovernance", stream_name: "AgentChoiceImpactScan" }
        ],
        event_types: %w[
          DecisionActivated
          DecisionDefinitionCorrected
          AgentChoiceAccepted
          AgentChoiceImpactScanStarted
          AgentChoiceImpactScanProgressed
        ]
      }
    )
  end

  def repository_scope
    InterpretationInput.scope(repository_ids: [ RepositoryScenario::DEFAULT_REPOSITORY_ID ])
  end

  def scan_id(source)
    Coordinator::Write::AgentChoiceImpacts::ScanIdentityBuilder.new.start(
      source_event: reference(source),
      policy_version: AgentChoiceImpactScenario::POLICY_VERSION
    )
  end

  def scan_events(source)
    event_store.read_grouped(
      streams.agent_choice_impact_scan(scan_id(source)),
      Coordinator::Write::EventQueries::AGENT_CHOICE_IMPACT_SCAN_STATE
    )
  end

  def scan_event(source, type, required: true)
    event = scan_events(source).find { _1.type == type }
    raise "missing #{type} for #{scan_id(source)}" if required && !event

    event
  end

  def assessment_id(choice, source)
    Coordinator::Write::AgentChoiceImpacts::AssessmentIdentityBuilder.new.call(
      accepted_choice: reference(choice.fetch(:accepted)),
      decision_change: reference(source),
      policy_version: AgentChoiceImpactScenario::POLICY_VERSION
    )
  end

  def assessment_events(choice, source)
    event_store.read(
      streams.agent_choice_impact(assessment_id(choice, source)),
      Coordinator::Write::EventQueries::AGENT_CHOICE_IMPACT_ASSESSMENT
    )
  end

  def choice_events(choice)
    event_store.read(
      streams.agent_choice(choice.fetch(:identifiers).fetch(:choice_id)),
      Coordinator::Write::EventQueries::AGENT_CHOICE_FOR_IMPACT
    )
  end

  def load(event)
    schemas.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def reference(event)
    Coordinator::Processes::AgentChoiceImpacts::EventReferenceBuilder.new.call(event)
  end
end

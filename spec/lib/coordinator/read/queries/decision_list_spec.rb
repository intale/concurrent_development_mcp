# frozen_string_literal: true

RSpec.describe Coordinator::Read::Queries::DecisionList, :event_store, :read_model do
  subject(:query) { described_class.new }

  REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000021"
  OTHER_REPOSITORY_ID = "018f0f4d-4e45-7abc-8def-000000000022"

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:decision_projector) { Coordinator::Read::Projectors::DecisionGovernanceV1.new }

  it "discovers active Decision topics associated directly and through projected coordination" do
    change_set_id = seed_coordination
    activate_decision(
      suffix: "impact",
      decision_id: "D-impact",
      proposal: InterpretationInput.impact_policy(
        level: "advisory",
        change_set_id:,
        command_id: "cmd-proposal-impact",
        interpretation_id: "I-impact",
        source_message_id: "M-impact"
      )
    )
    activate_decision(
      suffix: "testing",
      decision_id: "D-testing",
      proposal: InterpretationInput.build(
        command_id: "cmd-proposal-testing",
        interpretation_id: "I-testing",
        source_message_id: "M-testing",
        scope: InterpretationInput.scope(repository_ids: [ REPOSITORY_ID ])
      )
    )
    %w[D-impact D-testing].each { project_decision(_1) }

    impact = query.call(
      repository_id: REPOSITORY_ID,
      topic_id: "candidate.impact_policy",
      policy_status: "active"
    ).value!
    expect(impact).to have_attributes(status: "ok")
    expect(impact.warnings).to contain_exactly(match(/projection-derived/))
    expect(impact.data.page.items.map(&:decision_id)).to eq([ "D-impact" ])
    expect(impact.next_actions.sole).to have_attributes(
      tool: "decision_get",
      arguments: have_attributes(decision_id: "D-impact")
    )

    all_topics = query.call(repository_id: REPOSITORY_ID, limit: 1).value!
    expect(all_topics.data.page).to have_attributes(has_more: true, next_decision_id: "D-impact")
    continued = query.call(
      repository_id: REPOSITORY_ID,
      after_decision_id: all_topics.data.page.next_decision_id,
      limit: 1
    ).value!
    expect(
      [ *all_topics.data.page.items, *continued.data.page.items ].map(&:decision_id)
    ).to eq(%w[D-impact D-testing])

    unrelated = query.call(repository_id: OTHER_REPOSITORY_ID).value!
    expect(unrelated.data.page.items).to be_empty
  end

  it "serves the available Decision page while a newer activation is not projected" do
    activate_decision(
      suffix: "available",
      decision_id: "D-available",
      proposal: InterpretationInput.build(
        command_id: "cmd-proposal-available",
        interpretation_id: "I-available",
        source_message_id: "M-available",
        scope: InterpretationInput.scope(repository_ids: [ REPOSITORY_ID ])
      )
    )
    activate_decision(
      suffix: "unprojected",
      decision_id: "D-unprojected",
      proposal: InterpretationInput.build(
        command_id: "cmd-proposal-unprojected",
        interpretation_id: "I-unprojected",
        source_message_id: "M-unprojected",
        source_span: { start_character: 4, end_character: 10, text: "suites" },
        statement_kind: "directive",
        topic_id: "testing.required_suites",
        effect: "require",
        modality: "must",
        value: InterpretationInput.string_set(%w[cucumber rspec]),
        scope: InterpretationInput.scope(repository_ids: [ REPOSITORY_ID ])
      )
    )
    project_decision("D-available")

    result = query.call(repository_id: REPOSITORY_ID).value!

    expect(result.data.page.items.map(&:decision_id)).to eq([ "D-available" ])
    expect(result.to_h.keys & %i[fresh pending projection_status stream_revision]).to be_empty
  end

  it "returns typed invalid filters and an empty available page" do
    invalid = query.call(
      repository_id: "billing",
      topic_id: "bad topic",
      policy_status: "retired",
      limit: 51
    ).value!
    empty = query.call(repository_id: REPOSITORY_ID).value!

    expect(invalid).to have_attributes(status: "invalid")
    expect(invalid.data).to have_attributes(code: "invalid_input")
    expect(empty.data.page).to have_attributes(items: [], has_more: false)
  end

  def seed_coordination
    register_repository(REPOSITORY_ID, "project:decision-discovery")
    register_repository(OTHER_REPOSITORY_ID, "project:other")
    change_set_id = "CS-decision-discovery"
    work_item_id = "W-decision-discovery"
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "cmd-decision-discovery-create",
      actor: { kind: "agent", id: "planner" },
      change_set_id:,
      goal: "Discover ChangeSet policy",
      acceptance_criteria: [ "Policy is available by Repository" ]
    })
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "cmd-decision-discovery-work-item",
      actor: { kind: "agent", id: "planner" },
      change_set_id:,
      work_item_id:,
      repository_id: REPOSITORY_ID,
      goal: "Implement the policy",
      acceptance_criteria: [ "The policy applies to this Repository" ]
    })
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "cmd-decision-discovery-activate",
      actor: { kind: "agent", id: "planner" },
      change_set_id:
    })
    project_coordination(change_set_id:, work_item_id:)
    change_set_id
  end

  def register_repository(repository_id, scope)
    suffix = repository_id[-4, 4]
    execute(Coordinator::Write::Operations::ExecuteRegisterRepository, {
      command_id: "cmd-register-#{suffix}",
      actor: { kind: "agent", id: "repository-registrar" },
      repository_id:,
      scope:,
      repository_key: "repository-#{suffix}",
      display_name: "Repository #{suffix}",
      paths: [],
      remotes: []
    })
    event = event_store.read(
      streams.repository(repository_id),
      Coordinator::Write::EventQueries::REPOSITORY_REGISTRATION
    ).sole
    Coordinator::Read::Projectors::RepositoriesV1.new.call(event)
  end

  def activate_decision(suffix:, decision_id:, proposal:)
    message_id = proposal.fetch(:source_message_id)
    interpretation_id = proposal.fetch(:interpretation_id)
    source_span = proposal.fetch(:source_span)
    guidance_text = if source_span
      "Use #{source_span.fetch(:text)}."
    else
      "Record #{proposal.dig(:proposed_decision, :topic_id)} policy."
    end
    execute(Coordinator::Write::Operations::ExecuteRecordGuidance, {
      command_id: "cmd-guidance-#{suffix}",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-#{suffix}",
      source: "mcp_client",
      text: guidance_text,
      anchors: {
        repository_ids: [ REPOSITORY_ID ],
        change_set_id: proposal.dig(:proposed_decision, :scope, :change_set_id),
        work_item_id: nil,
        attempt_id: nil
      }
    })
    execute(Coordinator::Write::Operations::ExecuteProposeDecisionInterpretation, proposal)
    execute(
      Coordinator::Write::Operations::ExecuteAdjudicateDecisionInterpretation,
      InterpretationInput.adjudication(
        command_id: "cmd-adjudicate-#{suffix}",
        source_message_id: message_id,
        interpretation_id:
      )
    )
    execute(
      Coordinator::Write::Operations::ExecuteActivateDecision,
      InterpretationInput.activation(
        command_id: "cmd-activate-#{suffix}",
        decision_id:,
        interpretation_id:
      )
    )
  end

  def project_decision(decision_id)
    event_store.read(streams.decision(decision_id), Coordinator::Write::EventQueries::DECISION_EXISTENCE)
      .each { decision_projector.call(_1) }
  end

  def project_coordination(change_set_id:, work_item_id:)
    events = [
      [ streams.change_set(change_set_id), 1_103 ],
      [ streams.work_item(work_item_id), 10 ]
    ].flat_map do |stream, maximum_count|
      event_store.read(
        stream,
        Coordinator::Write::EventReadCriteria.new(
          event_types: Coordinator::Read::Contracts::CoordContextSourceEvent::EVENT_STREAMS.keys,
          maximum_count:,
          direction: :asc
        )
      )
    end
    events.sort_by(&:global_position).each do |event|
      Coordinator::Read::Projectors::CoordContextV1.new.call(event)
    end
  end

  def execute(operation_class, arguments)
    operation_class.new(event_store:).call(arguments).value!
  end
end

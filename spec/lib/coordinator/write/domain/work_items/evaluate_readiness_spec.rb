# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::WorkItems::EvaluateReadiness do
  subject(:decider) { described_class.new }

  let(:occurred_at) { "2026-08-20T14:15:01.000000Z" }
  let(:command) { readiness_command("W-100") }
  let(:change_set_state) do
    Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_id: "CS-100",
      goal: "Coordinate billing changes",
      status: "active",
      acceptance_criteria: [ "Agents do not overlap" ],
      work_item_ids: [ "W-100" ],
      dependencies: []
    )
  end
  let(:work_item_state) do
    Coordinator::Write::Domain::WorkItems::State.new(
      work_item_id: "W-100",
      change_set_id: "CS-100",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal: "Implement capture validation",
      acceptance_criteria: [ "The work is verifiable" ],
      status: "planned"
    )
  end

  it "implements PLN-READY-TARGET-SUCCESS-01 as a one-event command decision" do
    result = decider.call(
      change_set_state:,
      work_item_state:,
      command:,
      occurred_at:,
      decision_recorded: false
    )

    expect(result).to be_success
    write = result.value!.writes.sole
    expect(write.stream.to_h).to eq(
      context: "DevelopmentExecution",
      stream_name: "WorkItem",
      stream_id: "W-100"
    )
    expect(write.event).to eq(
      Coordinator::Write::Events::WorkItemMadeReadyV2.new(
        change_set_id: "CS-100",
        work_item_id: "W-100",
        readiness_decision_id: command.command_id,
        reason: "change_set_activated"
      )
    )
  end

  it "returns explicit zero-event outcomes for every first-slice invariant" do
    inactive = Coordinator::Write::Domain::ChangeSets::State.new(change_set_state.to_h.merge(status: "draft"))
    no_member = Coordinator::Write::Domain::ChangeSets::State.new(change_set_state.to_h.merge(work_item_ids: []))
    mismatch = Coordinator::Write::Domain::WorkItems::State.new(
      work_item_state.to_h.merge(change_set_id: "CS-other")
    )
    ready = Coordinator::Write::Domain::WorkItems::State.new(work_item_state.to_h.merge(status: "ready"))
    dependency = Coordinator::Write::Domain::ChangeSets::Dependency.new(
      dependency_id: "DEP-1",
      producer_work_item_id: "W-200",
      consumer_work_item_id: "W-100",
      dependency_kind: "requires_candidate",
      required_output: nil
    )
    blocked = Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_state.to_h.merge(dependencies: [ dependency ])
    )
    scenarios = [
      [ change_set_state, work_item_state, true, :readiness_already_decided ],
      [ inactive, work_item_state, false, :change_set_not_active ],
      [ no_member, work_item_state, false, :work_item_not_member ],
      [ change_set_state, Coordinator::Write::Domain::WorkItems::State.initial, false, :work_item_not_found ],
      [ change_set_state, mismatch, false, :work_item_change_set_mismatch ],
      [ change_set_state, ready, false, :work_item_already_ready ],
      [ blocked, work_item_state, false, :incoming_dependency_unsatisfied ]
    ]

    aggregate_failures do
      scenarios.each do |change_set, work_item, decision_recorded, code|
        result = decider.call(
          change_set_state: change_set,
          work_item_state: work_item,
          command:,
          occurred_at:,
          decision_recorded:
        )

        expect(result).to be_failure
        expect(result.failure.code).to eq(code)
      end
    end
  end

  it "allows activation evaluation when every incoming edge already has a satisfaction fact" do
    dependency = Coordinator::Write::Domain::ChangeSets::Dependency.new(
      dependency_id: "DEP-1",
      producer_work_item_id: "W-200",
      consumer_work_item_id: "W-100",
      dependency_kind: "requires_candidate",
      required_output: nil
    )
    satisfaction = Coordinator::Write::Domain::ChangeSets::DependencySatisfaction.new(
      dependency_id: "DEP-1",
      source_event: command.decision_identity.document.source_event,
      satisfied_at: occurred_at
    )
    satisfied = Coordinator::Write::Domain::ChangeSets::State.new(
      change_set_state.to_h.merge(
        dependencies: [ dependency ],
        dependency_satisfactions: [ satisfaction ]
      )
    )

    result = decider.call(
      change_set_state: satisfied,
      work_item_state:,
      command:,
      occurred_at:,
      decision_recorded: false
    )

    expect(result).to be_success
  end

  def readiness_command(work_item_id)
    source_reference = Coordinator::Write::EventReference.new(
      event_id: "0198c000-0000-7000-8000-000000000001",
      type: "ChangeSetActivated",
      stream_context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      stream_id: "CS-100",
      stream_revision: 4
    )
    document = Coordinator::Write::ProcessDecisions::ReadinessV1.new(
      schema: "process-decision/readiness/v1",
      process_manager: "change-set-readiness",
      policy_version: "change-set-readiness/v1",
      source_event: source_reference,
      target_work_item_id: work_item_id,
      process_step: "evaluate-work-item-readiness"
    )
    marker = Coordinator::Shared::CompoundMarkerBuilder.new.call(
      Coordinator::Shared::CompoundMarkerDefinitionV1.new(
        purpose: "process-decision",
        components: document.component_markers
      )
    )
    command_id = SecureRandom.uuid_v7

    Coordinator::Write::Commands::EvaluateWorkItemReadiness.new(
      command_id:,
      actor: Coordinator::Write::Commands::Actor.new(kind: "system", id: "change-set-readiness"),
      change_set_id: "CS-100",
      work_item_id:,
      source_activation_event_id: source_reference.event_id,
      source_activation_revision: source_reference.stream_revision,
      policy_version: "change-set-readiness/v1",
      decision_identity: Coordinator::Write::ReadinessDecisionIdentity.new(
        document:,
        compound_marker: marker,
        command_id:
      )
    )
  end
end

# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteEvaluateWorkItemReadiness, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "persists WorkItemMadeReady with the full compound identity and source causation" do
    activation = seed_activated_change_set(change_set_id: "CS-100", work_item_ids: [ "W-100" ])
    invocation = invocation_for(activation, work_item_id: "W-100")

    result = operation.call(invocation)

    expect(result).to be_success
    made_ready = readiness_events("W-100").sole
    command = invocation.command
    expect(made_ready.data).to eq(
      "change_set_id" => "CS-100",
      "work_item_id" => "W-100",
      "readiness_decision_id" => command.command_id,
      "reason" => "change_set_activated",
      "made_ready_at" => made_ready.data.fetch("made_ready_at")
    )
    expect(made_ready.data.fetch("made_ready_at")).to match(Coordinator::Shared::Types::TIMESTAMP_PATTERN)
    expect(made_ready.markers).to eq(
      (command.process_decision_components + [
        command.process_decision_marker,
        "change-set:CS-100",
        "work-item:W-100",
        "repository:billing",
        "command:#{command.command_id}"
      ]).uniq.sort
    )
    expect(made_ready.causation_id).to eq(activation.id)
    expect(made_ready.correlation_id).to eq(activation.correlation_id)
    expect(made_ready.metadata).to include(
      "command_id" => command.command_id,
      "actor_kind" => "system",
      "actor_id" => "change-set-readiness",
      "policy_version" => "change-set-readiness/v1",
      "schema_version" => 1
    )
    expect(work_item_state("W-100").status).to eq("ready")
    expect(command_events(command.command_id)).to be_empty
  end

  it "handles exact redelivery as an explicit zero-event decision" do
    activation = seed_activated_change_set(change_set_id: "CS-100", work_item_ids: [ "W-100" ])
    invocation = invocation_for(activation, work_item_id: "W-100")

    first = operation.call(invocation)
    duplicate = operation.call(invocation)

    expect(first).to be_success
    expect(duplicate).to be_failure
    expect(duplicate.failure.code).to eq(:readiness_already_decided)
    expect(readiness_events("W-100").length).to eq(1)
  end

  it "serializes concurrent duplicate process decisions in the real store" do
    activation = seed_activated_change_set(change_set_id: "CS-100", work_item_ids: [ "W-100" ])
    invocation = invocation_for(activation, work_item_id: "W-100")

    results = 2.times.map do
      Thread.new { described_class.new(event_store:).call(invocation) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(:readiness_already_decided)
    expect(readiness_events("W-100").length).to eq(1)
  end

  it "emits no readiness fact while an incoming dependency lacks a satisfaction fact" do
    activation = seed_activated_change_set(
      change_set_id: "CS-100",
      work_item_ids: [ "W-100", "W-200" ],
      dependency: [ "W-100", "W-200" ]
    )
    invocation = invocation_for(activation, work_item_id: "W-200")

    result = operation.call(invocation)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:incoming_dependency_unsatisfied)
    expect(readiness_events("W-200")).to be_empty
  end

  def seed_activated_change_set(change_set_id:, work_item_ids:, dependency: nil)
    create_change_set(change_set_id)
    work_item_ids.each { create_work_item(change_set_id, _1) }
    declare_dependency(change_set_id, *dependency) if dependency

    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    ).value!

    change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
  end

  def create_change_set(change_set_id)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate #{change_set_id}",
      acceptance_criteria: [ "Agents do not overlap" ]
    ).value!
  end

  def create_work_item(change_set_id, work_item_id)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id: "billing",
      goal: "Implement #{work_item_id}",
      acceptance_criteria: [ "The work is verifiable" ]
    ).value!
  end

  def declare_dependency(change_set_id, producer_work_item_id, consumer_work_item_id)
    Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency.new(event_store:).call(
      command_id: "seed-dependency-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      dependency_id: "DEP-1",
      producer_work_item_id:,
      consumer_work_item_id:,
      dependency_kind: "requires_candidate",
      required_output: nil
    ).value!
  end

  def invocation_for(activation, work_item_id:)
    source = Coordinator::Processes::ChangeSetActivationSourceBuilder.new.call(activation)
    command = Coordinator::Processes::ReadinessCommandBuilder.new.call(source:, work_item_id:)

    Coordinator::Write::ReadinessInvocation.new(
      command:,
      source_event: source.event,
      source_reference: source.reference,
      source_change_set_id: source.payload.change_set_id
    )
  end

  def change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
  end

  def work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_READINESS_EVALUATION
    )
  end

  def readiness_events(work_item_id)
    work_item_events(work_item_id).select { _1.type == "WorkItemMadeReady" }
  end

  def work_item_state(work_item_id)
    schemas = Coordinator::Write::EventSchemaRegistry.new
    events = work_item_events(work_item_id).map do |event|
      schemas.load(
        type: event.type,
        schema_version: event.metadata.fetch("schema_version"),
        data: event.data
      )
    end
    Coordinator::Write::Domain::WorkItems::State.reduce(events)
  end

  def command_events(command_id)
    event_store.read(streams.command(command_id), Coordinator::Write::EventQueries::COMMAND_COMPLETION)
  end
end

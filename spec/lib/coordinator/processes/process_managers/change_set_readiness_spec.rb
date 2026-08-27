# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::ChangeSetReadiness, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:process_manager) { described_class.new(event_store:) }

  it "issues idempotent per-target commands while appending no downstream event itself" do
    activation = seed_activated_change_set(
      change_set_id: "CS-100",
      work_item_ids: [ "W-100", "W-200" ],
      dependency: [ "W-100", "W-200" ]
    )

    first = process_manager.call(activation)
    redelivery = process_manager.call(activation)

    expect(first).to be_nil
    expect(redelivery).to be_nil
    expect(readiness_events("W-100").length).to eq(1)
    expect(readiness_events("W-200")).to be_empty
    made_ready = readiness_events("W-100").sole
    expect(made_ready.metadata).to include(
      "actor_kind" => "system",
      "actor_id" => "change-set-readiness",
      "policy_version" => "change-set-readiness/v1"
    )
    expect(made_ready.causation_id).to eq(activation.id)
  end

  it "handles a real filtered pg_eventstore subscription from activation to readiness" do
    create_change_set("CS-100")
    create_work_item("CS-100", "W-100")
    registration = Coordinator::Processes::Subscriptions::ChangeSetReadiness.new(
      handler: process_manager,
      pull_interval: 0.2
    )
    subscription_set = build_subscription_set([ registration ])

    begin
      subscription_set.start
      activation = activate_change_set("CS-100")
      wait_for_subscription(subscription_set, registration.definition.subscription_name)

      made_ready = readiness_events("W-100").sole
      expect(made_ready.causation_id).to eq(activation.id)
      expect(made_ready.correlation_id).to eq(activation.correlation_id)
    ensure
      subscription_set.stop
    end
  end

  it "stacks every registration for the set on one subscriptions manager" do
    readiness = Coordinator::Processes::Subscriptions::ChangeSetReadiness.new(handler: process_manager)
    audit = Coordinator::Shared::Subscriptions::Registration.new(
      definition: Coordinator::Shared::Subscriptions::Definition.new(
        set_name: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME,
        subscription_name: "process-manager-audit-probe-v1",
        stream_context: "DevelopmentPlanning",
        stream_name: "ChangeSet",
        event_types: [ "ChangeSetActivated" ]
      ),
      handler: ->(_event) { }
    )

    subscription_set = build_subscription_set([ readiness, audit ])

    expect(subscription_set.subscription_names).to eq(
      [ "change-set-readiness-v1", "process-manager-audit-probe-v1" ]
    )
  end

  it "publishes the frozen subscription filter through a typed definition" do
    definition = Coordinator::Processes::Subscriptions::ChangeSetReadiness::DEFINITION

    expect(definition.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "change-set-readiness-v1",
      stream_context: "DevelopmentPlanning",
      stream_name: "ChangeSet",
      event_types: [ "ChangeSetActivated" ],
      event_markers: []
    )
    expect(definition.options).to eq(
      filter: {
        streams: [ { context: "DevelopmentPlanning", stream_name: "ChangeSet" } ],
        event_types: [ "ChangeSetActivated" ]
      }
    )
  end

  def seed_activated_change_set(change_set_id:, work_item_ids:, dependency: nil)
    RepositoryScenario.register(event_store:)
    create_change_set(change_set_id)
    work_item_ids.each { create_work_item(change_set_id, _1) }
    declare_dependency(change_set_id, *dependency) if dependency
    activate_change_set(change_set_id)
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
    RepositoryScenario.register(event_store:)
    Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
      command_id: "seed-create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      work_item_id:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
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

  def activate_change_set(change_set_id)
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-#{change_set_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    ).value!

    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    ).find { _1.type == "ChangeSetActivated" }
  end

  def readiness_events(work_item_id)
    event_store.read_grouped(
      streams.work_item(work_item_id),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_READINESS_EVALUATION
    ).reverse.select { _1.type == "WorkItemMadeReady" }
  end

  def build_subscription_set(registrations)
    manager = PgEventstore.subscriptions_manager(
      subscription_set: Coordinator::Processes::Subscriptions::ProcessManagerSet::SET_NAME
    )
    Coordinator::Processes::Subscriptions::ProcessManagerSet.new(manager:, registrations:)
  end

  def wait_for_subscription(subscription_set, subscription_name)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10

    until subscription_set.processed_event_count(subscription_name) >= 1
      raise "readiness subscription did not process the activation within 10 seconds" if
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end
end

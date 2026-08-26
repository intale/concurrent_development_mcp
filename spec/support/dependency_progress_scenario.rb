# frozen_string_literal: true

module DependencyProgressScenario
  module_function

  def prepare(prefix:, dependency_kind:, required_output: nil)
    RepositoryScenario.register(event_store:)
    ids = {
      change_set_id: "CS-progress-#{prefix}",
      producer_work_item_id: "W-progress-#{prefix}-producer",
      consumer_work_item_id: "W-progress-#{prefix}-consumer",
      attempt_id: "A-progress-#{prefix}",
      candidate_id: "CAN-progress-#{prefix}"
    }
    create_change_set(ids)
    create_work_item(ids, work_item_id: ids.fetch(:producer_work_item_id), goal: "Produce dependency evidence")
    create_work_item(ids, work_item_id: ids.fetch(:consumer_work_item_id), goal: "Consume dependency evidence")
    declare_dependency(ids, dependency_kind:, required_output:)
    activation = activate(ids)
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    acquire(ids)
    reservation = reserve(ids)
    candidate_input = submit_candidate(ids, reservation:)

    { ids:, reservation:, candidate_input:, activation: }
  end

  def complete(scenario, produced_outputs: [])
    ids = scenario.fetch(:ids)
    input = scenario.fetch(:candidate_input)
    reservation = scenario.fetch(:reservation)
    execute(Coordinator::Write::Operations::ExecuteReleaseLeaseSet, {
      command_id: "release-progress-#{ids.fetch(:candidate_id)}",
      actor: input.fetch(:actor),
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |lease|
        {
          resource_key_hash: lease.resource_key_hash,
          lease_id: lease.lease_id,
          fencing_token: lease.fencing_token
        }
      end
    })
    completion = execute(Coordinator::Write::Operations::ExecuteCompleteWorkItem, {
      command_id: "complete-progress-#{ids.fetch(:candidate_id)}",
      actor: input.fetch(:actor),
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      candidate_id: ids.fetch(:candidate_id),
      produced_outputs:
    })
    scenario.merge(work_item_completion: completion)
  end

  def work_item_event(scenario, type)
    events = event_store.read_grouped(
      streams.work_item(scenario.dig(:ids, :producer_work_item_id)),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_COMPLETION
    ).reverse
    events.find { _1.type == type }
  end

  def dependency_events(scenario)
    event_store.read(
      streams.change_set(scenario.dig(:ids, :change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_DEPENDENCY_SATISFACTION
    ).select { _1.type == "WorkItemDependencySatisfied" }
  end

  def readiness_events(scenario)
    event_store.read_grouped(
      streams.work_item(scenario.dig(:ids, :consumer_work_item_id)),
      Coordinator::Write::EventQueries::WORK_ITEM_FOR_READINESS_EVALUATION
    ).reverse.select { _1.type == "WorkItemMadeReady" }
  end

  def requeue_consumer(scenario, count:)
    ids = scenario.fetch(:ids)

    count.times do |index|
      attempt_id = "A-progress-#{ids.fetch(:candidate_id)}-consumer-#{index}"
      execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
        command_id: "acquire-#{attempt_id}",
        actor: { kind: "agent", id: "agent-b" },
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: ids.fetch(:consumer_work_item_id),
        attempt_id:,
        base_snapshots: [
          { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "d" * 40 }
        ]
      })
      execute(Coordinator::Write::Operations::ExecuteAbandonAttempt, {
        command_id: "abandon-#{attempt_id}",
        actor: { kind: "agent", id: "agent-b" },
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: ids.fetch(:consumer_work_item_id),
        attempt_id:,
        reason: "Checkpoint elsewhere"
      })
    end

    scenario
  end

  def create_change_set(ids)
    execute(Coordinator::Write::Operations::ExecuteCreateChangeSet, {
      command_id: "create-#{ids.fetch(:change_set_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      goal: "Coordinate dependency progress",
      acceptance_criteria: [ "Consumer starts only after exact producer evidence" ]
    })
  end

  def create_work_item(ids, work_item_id:, goal:)
    execute(Coordinator::Write::Operations::ExecuteCreateWorkItem, {
      command_id: "create-#{work_item_id}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id:,
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      goal:,
      acceptance_criteria: [ "Progress is attributable" ]
    })
  end

  def declare_dependency(ids, dependency_kind:, required_output:)
    execute(Coordinator::Write::Operations::ExecuteDeclareWorkItemDependency, {
      command_id: "declare-DEP-progress-#{ids.fetch(:candidate_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      dependency_id: "DEP-progress-#{ids.fetch(:candidate_id)}",
      producer_work_item_id: ids.fetch(:producer_work_item_id),
      consumer_work_item_id: ids.fetch(:consumer_work_item_id),
      dependency_kind:,
      required_output:
    })
  end

  def activate(ids)
    execute(Coordinator::Write::Operations::ExecuteActivateChangeSet, {
      command_id: "activate-#{ids.fetch(:change_set_id)}",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id)
    })
    event_store.read(
      streams.change_set(ids.fetch(:change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    ).find { _1.type == "ChangeSetActivated" }
  end

  def acquire(ids)
    execute(Coordinator::Write::Operations::ExecuteAcquireWorkItem, {
      command_id: "acquire-#{ids.fetch(:attempt_id)}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [
        { repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID, commit_oid: "a" * 40 }
      ]
    })
  end

  def reserve(ids)
    execute(Coordinator::Write::Operations::ExecuteReserveWriteSet, {
      command_id: "reserve-#{ids.fetch(:attempt_id)}",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      base_commit_oid: "a" * 40,
      resources: [ { kind: "file", path: "lib/progress.rb", base_blob_oid: "c" * 40 } ],
      lease_duration_seconds: 900
    }).data
  end

  def submit_candidate(ids, reservation:)
    input = {
      command_id: "candidate-#{ids.fetch(:candidate_id)}",
      actor: { kind: "agent", id: "agent-a" },
      candidate_id: ids.fetch(:candidate_id),
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid: "b" * 40,
      checkpoint_kind: "final",
      lease_set_id: reservation.lease_set_id,
      leases: reservation.resources.map do |lease|
        {
          resource_key_hash: lease.resource_key_hash,
          lease_id: lease.lease_id,
          fencing_token: lease.fencing_token
        }
      end,
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [ CandidateScenario.manifest_file("lib/progress.rb") ]
      }
    }
    execute(Coordinator::Write::Operations::ExecuteSubmitCandidate, input)
    input
  end

  def execute(operation_class, input)
    operation_class.new(event_store:).call(input).value!
  end

  def event_store
    Coordinator::Write::EventStore.new(client: PgEventstore.client)
  end

  def streams
    Coordinator::Write::StreamFactory.new
  end
end

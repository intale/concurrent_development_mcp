# frozen_string_literal: true

module ResourceLeaseOperationScenario
  Reservation = Data.define(:receipt, :resource_ids)

  module_function

  def start_attempts(event_store:, attempts:, repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID)
    streams = Coordinator::Write::StreamFactory.new
    RepositoryScenario.register(event_store:, repository_id:)
    Coordinator::Write::Operations::ExecuteCreateChangeSet.new(event_store:).call(
      command_id: "seed-create-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE",
      goal: "Coordinate resource work intentions",
      acceptance_criteria: [ "Exclusive overlapping work intentions cannot coexist" ]
    ).value!
    attempts.each do |work_item_id, _attempt_id, _agent_id|
      Coordinator::Write::Operations::ExecuteCreateWorkItem.new(event_store:).call(
        command_id: "seed-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id: "CS-LSE",
        work_item_id:,
        repository_id:,
        goal: "Implement #{work_item_id}",
        acceptance_criteria: [ "The work is verifiable" ]
      ).value!
    end
    Coordinator::Write::Operations::ExecuteActivateChangeSet.new(event_store:).call(
      command_id: "seed-activate-CS-LSE",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: "CS-LSE"
    ).value!
    activation = event_store.read(
      streams.change_set("CS-LSE"),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACQUISITION
    ).find { _1.type == "ChangeSetActivated" }
    Coordinator::Processes::ProcessManagers::ChangeSetReadiness.new(event_store:).call(activation)
    attempts.each do |work_item_id, attempt_id, agent_id|
      Coordinator::Write::Operations::ExecuteAcquireWorkItem.new(event_store:).call(
        command_id: "seed-acquire-#{attempt_id}",
        actor: { kind: "agent", id: agent_id },
        change_set_id: "CS-LSE",
        work_item_id:,
        attempt_id:,
        base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
      ).value!
    end
  end

  def reserve(
    event_store:,
    paths:,
    command_id: "seed-reserve-v2",
    agent_id: "agent-a",
    work_item_id: "W-LSE-A",
    attempt_id: "A-LSE-A",
    ttl_seconds: 900,
    repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID
  )
    targets = paths.map do |entry|
      attributes = entry.is_a?(String) ? { path: entry, kind: "file" } : entry
      resource_id = ResourceScenario.resolve(
        event_store:,
        repository_id:,
        kind: attributes.fetch(:kind),
        path: attributes.fetch(:path)
      )
      {
        resource_id:,
        base_blob_oid: attributes[:base_blob_oid],
        mode: attributes.fetch(:mode, "shared"),
        purpose: attributes.fetch(:purpose, "Coordinate #{attributes.fetch(:path)}"),
        context: attributes[:context]
      }
    end
    resource_ids = targets.map { _1.fetch(:resource_id) }
    result = Coordinator::Write::Operations::ExecuteReserveWriteSet.new(event_store:).call(
      command_id:,
      actor: { kind: "agent", id: agent_id },
      change_set_id: "CS-LSE",
      work_item_id:,
      attempt_id:,
      repository_id:,
      base_commit_oid: "a" * 40,
      resources: targets,
      ttl_seconds:
    )

    Reservation.new(receipt: result.value!.data, resource_ids:)
  end

  def work_intention_inputs(receipt)
    receipt.intentions.map do |reference|
      {
        resource_id: reference.resource_id,
        intention_id: reference.intention_id,
        fencing_token: reference.fencing_token
      }
    end
  end
end

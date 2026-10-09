# frozen_string_literal: true

module TerminalBuildProgressAcceptanceWorld
  def prepare_terminal_candidate(prefix:, agent_id:)
    coordination = prepare_candidate_coordination(
      prefix: "TERMINAL-#{prefix}",
      agent_id:,
      path: "lib/terminal_#{prefix.downcase}.rb"
    )
    coordination
  end

  def prepare_terminal_dependency(prefix:)
    repository_id = register_acceptance_repository
    ids = {
      change_set_id: "CS-CUC-TERMINAL-#{prefix}",
      producer_work_item_id: "W-CUC-TERMINAL-#{prefix}-PRODUCER",
      consumer_work_item_id: "W-CUC-TERMINAL-#{prefix}-CONSUMER",
      attempt_id: "A-CUC-TERMINAL-#{prefix}"
    }
    agent_id = "agent-terminal-dependency"
    complete_terminal_task(
      "change_set_create",
      command_id: "cmd-cuc-terminal-#{prefix}-create",
      actor: { kind: "agent", id: "planner-terminal" },
      change_set_id: ids.fetch(:change_set_id),
      goal: "Coordinate terminal dependency #{prefix}",
      acceptance_criteria: [ "Consumer waits for producer completion" ]
    )
    [
      [ ids.fetch(:producer_work_item_id), "Produce terminal evidence" ],
      [ ids.fetch(:consumer_work_item_id), "Consume terminal evidence" ]
    ].each do |work_item_id, goal|
      complete_terminal_task(
        "work_item_create",
        command_id: "cmd-cuc-terminal-create-#{work_item_id}",
        actor: { kind: "agent", id: "planner-terminal" },
        change_set_id: ids.fetch(:change_set_id),
        work_item_id:,
        repository_id:,
        goal:,
        acceptance_criteria: [ "Progress remains attributable" ]
      )
    end
    complete_terminal_task(
      "work_item_dependency_declare",
      command_id: "cmd-cuc-terminal-#{prefix}-dependency",
      actor: { kind: "agent", id: "planner-terminal" },
      change_set_id: ids.fetch(:change_set_id),
      dependency_id: "DEP-CUC-TERMINAL-#{prefix}",
      producer_work_item_id: ids.fetch(:producer_work_item_id),
      consumer_work_item_id: ids.fetch(:consumer_work_item_id),
      dependency_kind: "requires_completion",
      required_output: nil
    )
    complete_terminal_task(
      "change_set_activate",
      command_id: "cmd-cuc-terminal-#{prefix}-activate",
      actor: { kind: "agent", id: "planner-terminal" },
      change_set_id: ids.fetch(:change_set_id)
    )
    activation = change_set_events(ids.fetch(:change_set_id)).find { _1.type == "ChangeSetActivated" }
    assert_acceptance(activation, "Terminal dependency #{prefix} has no activation fact")
    await_work_item_ready(ids.fetch(:producer_work_item_id))
    complete_terminal_task(
      "work_item_acquire",
      command_id: "cmd-cuc-terminal-#{prefix}-acquire",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
    )
    reservation_task_id = complete_terminal_task(
      "work_intention_set_declare",
      command_id: "cmd-cuc-terminal-#{prefix}-reserve",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id:,
      base_commit_oid: "a" * 40,
      resources: [
        resource_target(
          kind: "file",
          path: "lib/terminal_dependency.rb",
          repository_id:,
          base_blob_oid: CandidateAcceptanceWorld::BASE_BLOB_OID,
          actor_id: agent_id
        )
      ],
      ttl_seconds: 900
    )
    reservation = terminal_task_data(reservation_task_id)
    candidate_coordination = {
      prefix:,
      agent_id:,
      path: "lib/terminal_dependency.rb",
      repository_id:,
      ids: {
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: ids.fetch(:producer_work_item_id),
        attempt_id: ids.fetch(:attempt_id)
      },
      reservation:
    }
    project_terminal_context_sources(ids)

    { ids:, candidate_coordination:, reservation:, agent_id: }
  end

  def recover_terminal_attempts(coordination, prefix:, interruption_count:)
    recovered = coordination
    repository_id = recovered.fetch(:repository_id)
    interruption_count.times do |index|
      ids = recovered.fetch(:ids)
      complete_terminal_task(
        "attempt_abandon",
        command_id: "cmd-cuc-terminal-#{prefix}-abandon-#{index}",
        actor: { kind: "agent", id: recovered.fetch(:agent_id) },
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: ids.fetch(:work_item_id),
        attempt_id: ids.fetch(:attempt_id),
        reason: "The terminal agent was interrupted before producing a Candidate."
      )

      next_attempt_id = "A-CUC-TERMINAL-#{prefix}-RECOVERY-#{index + 1}"
      complete_terminal_task(
        "work_item_acquire",
        command_id: "cmd-cuc-terminal-#{prefix}-reacquire-#{index}",
        actor: { kind: "agent", id: recovered.fetch(:agent_id) },
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: ids.fetch(:work_item_id),
        attempt_id: next_attempt_id,
        base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
      )
      reservation_task_id = complete_terminal_task(
        "work_intention_set_declare",
        command_id: "cmd-cuc-terminal-#{prefix}-reserve-recovery-#{index}",
        actor: { kind: "agent", id: recovered.fetch(:agent_id) },
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: ids.fetch(:work_item_id),
        attempt_id: next_attempt_id,
        repository_id:,
        base_commit_oid: "a" * 40,
        resources: [
          resource_target(
            kind: "file",
            path: recovered.fetch(:path),
            repository_id:,
            base_blob_oid: CandidateAcceptanceWorld::BASE_BLOB_OID,
            actor_id: recovered.fetch(:agent_id)
          )
        ],
        ttl_seconds: 900
      )
      recovered = recovered.merge(
        ids: ids.merge(attempt_id: next_attempt_id),
        reservation: terminal_task_data(reservation_task_id)
      )
    end

    project_terminal_reacquisition(recovered.fetch(:ids))
    recovered
  end

  def submit_terminal_candidate(coordination, prefix:)
    arguments = candidate_arguments(
      coordination,
      candidate_id: "CAN-CUC-TERMINAL-#{prefix}",
      command_id: "cmd-cuc-terminal-#{prefix}-candidate",
      head_character: "b"
    )
    task_id = submit_candidate_task(arguments)
    state = task_request("tasks/get", task_id)
    assert_acceptance(
      state.dig("result", "result", "isError") == false,
      "Terminal Candidate submission failed: #{state.dig("result", "result", "structuredContent").inspect}"
    )
    project_candidate_context(arguments.fetch(:candidate_id), arguments.fetch(:attempt_id))

    { arguments:, task_id: }
  end

  def release_terminal_write_set(coordination, prefix:)
    ids = coordination.fetch(:ids)
    reservation = coordination.fetch(:reservation)
    task_id = complete_terminal_task(
      "work_intention_set_withdraw",
      command_id: "cmd-cuc-terminal-#{prefix}-release",
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      intention_set_id: reservation.fetch("intention_set_id"),
      intentions: reservation.fetch("intentions").map do |reference|
        {
          resource_id: reference.fetch("resource_id"),
          intention_id: reference.fetch("intention_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end
    )
    withdrawals = reservation.fetch("intentions").map do |reference|
      terminal_work_intention_events(reference.fetch("intention_id"))
        .find { _1.type == "ResourceWorkIntentionWithdrawn" }
    end
    assert_acceptance(withdrawals.all?, "Terminal work-intention set has missing withdrawal facts")
    await_read_model("Terminal write set release to become available") do
      payload = terminal_context(attempt_id: ids.fetch(:attempt_id))
      attempt = payload.dig("data", "context", "attempts")&.find do |candidate|
        candidate.fetch("attempt_id") == ids.fetch(:attempt_id)
      end
      observed = attempt&.dig("work_intention_set", "withdrawn_at")
      [ !observed.nil?, payload ]
    end
    task_id
  end

  def complete_terminal_work_item(coordination, candidate, prefix:)
    ids = coordination.fetch(:ids)
    task_id = complete_terminal_task(
      "work_item_complete",
      command_id: "cmd-cuc-terminal-#{prefix}-complete",
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      candidate_id: candidate.fetch(:arguments).fetch(:candidate_id),
      produced_outputs: [ { kind: "contract", key: "terminal-contract-#{prefix.downcase}" } ]
    )
    { task_id:, state: task_request("tasks/get", task_id) }
  end

  def project_terminal_context_sources(ids)
    project_attempt_context(
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids[:work_item_id] || ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id)
    )
  end

  def terminal_work_item_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WorkItemCandidateSelected WorkItemCompleted],
        maximum_count: 2,
        direction: :asc
      )
    )
  end

  def terminal_full_work_item_lifecycle(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          WorkItemCreated
          WorkItemMadeReady
          WorkItemAcquired
          WorkItemRequeued
          WorkItemCandidateSelected
          WorkItemCompleted
        ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def project_terminal_reacquisition(ids)
    project_attempt_context(
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id)
    )
  end

  def terminal_attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "AttemptCompleted" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def terminal_work_intention_events(intention_id)
    event_store.read_grouped(
      streams.resource_work_intention(intention_id),
      Coordinator::Write::EventQueries::WORK_INTENTION_STATE
    )
  end

  def terminal_change_set_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "ChangeSetCompleted" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def terminal_dependency_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WorkItemDependencySatisfied" ],
        maximum_count: 500,
        direction: :asc
      )
    )
  end

  def terminal_readiness_events(work_item_id)
    event_store.read(
      streams.work_item(work_item_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "WorkItemMadeReady" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def terminal_context(**scope)
    call_tool("coord_context", scope).dig("result", "structuredContent")
  end

  def complete_terminal_task(tool, **arguments)
    task_id = submit_and_execute(tool, **arguments)
    assert_successful_task(task_id, "Terminal setup #{tool}")
    task_id
  end

  def terminal_task_data(task_id)
    task_request("tasks/get", task_id).dig("result", "result", "structuredContent", "data")
  end
end

World(TerminalBuildProgressAcceptanceWorld)

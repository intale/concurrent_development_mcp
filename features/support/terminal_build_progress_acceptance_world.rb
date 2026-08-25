# frozen_string_literal: true

module TerminalBuildProgressAcceptanceWorld
  def prepare_terminal_candidate(prefix:, agent_id:)
    coordination = prepare_candidate_coordination(
      prefix: "TERMINAL-#{prefix}",
      agent_id:,
      path: "lib/terminal_#{prefix.downcase}.rb"
    )
    coordination.merge(repository_id: "billing")
  end

  def prepare_terminal_dependency(prefix:)
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
        repository_id: "billing",
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
    Coordinator::Container["process_managers.change_set_readiness"].call(activation)
    complete_terminal_task(
      "work_item_acquire",
      command_id: "cmd-cuc-terminal-#{prefix}-acquire",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [ { repository_id: "billing", commit_oid: "a" * 40 } ]
    )
    reservation_task_id = complete_terminal_task(
      "write_set_reserve",
      command_id: "cmd-cuc-terminal-#{prefix}-reserve",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:producer_work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: "billing",
      base_commit_oid: "a" * 40,
      resources: [
        {
          kind: "file",
          path: "lib/terminal_dependency.rb",
          base_blob_oid: CandidateAcceptanceWorld::BASE_BLOB_OID
        }
      ],
      lease_duration_seconds: 900
    )
    reservation = terminal_task_data(reservation_task_id)
    candidate_coordination = {
      prefix:,
      agent_id:,
      path: "lib/terminal_dependency.rb",
      repository_id: "billing",
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
    project_candidate_attachment(arguments.fetch(:candidate_id), arguments.fetch(:attempt_id))

    { arguments:, task_id: }
  end

  def release_terminal_write_set(coordination, prefix:)
    ids = coordination.fetch(:ids)
    reservation = coordination.fetch(:reservation)
    task_id = complete_terminal_task(
      "lease_release",
      command_id: "cmd-cuc-terminal-#{prefix}-release",
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      lease_set_id: reservation.fetch("lease_set_id"),
      leases: reservation.fetch("resources").map do |reference|
        {
          resource_key_hash: reference.fetch("resource_key_hash"),
          lease_id: reference.fetch("lease_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end
    )
    release = terminal_attempt_events(ids.fetch(:attempt_id)).find { _1.type == "WriteSetReleased" }
    assert_acceptance(release, "Terminal write set has no release fact")
    Coordinator::Container["projectors.coord_context_v1"].call(release)
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
    work_item_ids = [ ids[:work_item_id], ids[:producer_work_item_id], ids[:consumer_work_item_id] ].compact
    events = event_store.read(
      streams.change_set(ids.fetch(:change_set_id)),
      Coordinator::Write::EventQueries::CHANGE_SET_FOR_ACTIVATION
    )
    work_item_ids.each do |work_item_id|
      events += event_store.read(
        streams.work_item(work_item_id),
        Coordinator::Write::EventReadCriteria.new(
          event_types: %w[WorkItemCreated WorkItemMadeReady WorkItemAcquired],
          maximum_count: 3,
          direction: :asc
        )
      )
    end
    events += event_store.read(
      streams.attempt(ids.fetch(:attempt_id)),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[AttemptAuthorized AttemptStarted WriteSetReserved],
        maximum_count: 3,
        direction: :asc
      )
    )
    projector = Coordinator::Container["projectors.coord_context_v1"]
    events.sort_by(&:global_position).each { projector.call(_1) }
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

  def terminal_attempt_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[WriteSetReleased AttemptCompleted],
        maximum_count: 2,
        direction: :asc
      )
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

  def terminal_dependency_events(change_set_id)
    event_store.read(
      streams.change_set(change_set_id),
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

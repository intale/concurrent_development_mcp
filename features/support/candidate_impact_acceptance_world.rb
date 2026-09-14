# frozen_string_literal: true

module CandidateImpactAcceptanceWorld
  def prepare_impact_change_set(prefix:, rows:)
    change_set_id = "CS-CUC-IMP-#{prefix}"
    complete_candidate_setup_task(
      "change_set_create",
      command_id: "cmd-cuc-imp-#{prefix.downcase}-create",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:,
      goal: "Coordinate Candidate impact evidence #{prefix}",
      acceptance_criteria: [ "Potential impact remains attributed and available" ]
    )

    grouped = rows.group_by { [ _1.fetch("repository"), _1.fetch("path") ] }
    coordinations = grouped.keys.each_with_index.to_h do |(repository_label, path), index|
      sequence = index + 1
      work_item_id = "W-CUC-IMP-#{prefix}-#{sequence}"
      attempt_id = "A-CUC-IMP-#{prefix}-#{sequence}"
      agent_id = "impact-agent-#{sequence}"
      repository_id = register_acceptance_repository(repository_label)
      complete_candidate_setup_task(
        "work_item_create",
        command_id: "cmd-cuc-imp-#{prefix.downcase}-work-#{sequence}",
        actor: { kind: "agent", id: "planner-1" },
        change_set_id:,
        work_item_id:,
        repository_id:,
        goal: "Produce #{repository_label} Candidate evidence",
        acceptance_criteria: [ "The Candidate can publish impact evidence" ]
      )
      [ [ repository_label, path ], { work_item_id:, attempt_id:, agent_id:, repository_id:, path: } ]
    end

    complete_candidate_setup_task(
      "change_set_activate",
      command_id: "cmd-cuc-imp-#{prefix.downcase}-activate",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id:
    )
    activation = change_set_events(change_set_id).find { _1.type == "ChangeSetActivated" }
    assert_acceptance(activation, "Impact setup #{prefix} has no activation fact")
    coordinations.each_value { await_work_item_ready(_1.fetch(:work_item_id)) }

    coordinations.each_value do |coordination|
      acquire_and_reserve_impact_coordination(prefix:, change_set_id:, coordination:)
    end

    rows.to_h do |row|
      role = row.fetch("role")
      coordination = coordinations.fetch([ row.fetch("repository"), row.fetch("path") ])
      arguments = candidate_arguments(
        coordination.merge(ids: {
          change_set_id:,
          work_item_id: coordination.fetch(:work_item_id),
          attempt_id: coordination.fetch(:attempt_id)
        }),
        candidate_id: row.fetch("candidate_id"),
        command_id: "cmd-cuc-imp-#{prefix.downcase}-candidate-#{role.tr('_', '-')}",
        head_character: row.fetch("head"),
        build_context: row.fetch("observes_path") == "yes"
      )
      task_id = submit_candidate_task(arguments)
      assert_successful_task(task_id, "Impact Candidate #{role}")
      project_complete_candidate(arguments.fetch(:candidate_id), coordination.fetch(:attempt_id))
      [
        role,
        {
          arguments:,
          coordination: coordination.merge(
            ids: {
              change_set_id:,
              work_item_id: coordination.fetch(:work_item_id),
              attempt_id: coordination.fetch(:attempt_id)
            }
          ),
          task_id:,
          baseline: candidate_impact_view(arguments.fetch(:candidate_id))
        }
      ]
    end
  end

  def acquire_and_reserve_impact_coordination(prefix:, change_set_id:, coordination:)
    sequence = coordination.fetch(:attempt_id).split("-").last
    complete_candidate_setup_task(
      "work_item_acquire",
      command_id: "cmd-cuc-imp-#{prefix.downcase}-acquire-#{sequence}",
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      change_set_id:,
      work_item_id: coordination.fetch(:work_item_id),
      attempt_id: coordination.fetch(:attempt_id),
      base_snapshots: [
        { repository_id: coordination.fetch(:repository_id), commit_oid: CandidateAcceptanceWorld::BASE_COMMIT_OID }
      ]
    )
    reservation_task_id = complete_candidate_setup_task(
      "work_intention_set_declare",
      command_id: "cmd-cuc-imp-#{prefix.downcase}-reserve-#{sequence}",
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      change_set_id:,
      work_item_id: coordination.fetch(:work_item_id),
      attempt_id: coordination.fetch(:attempt_id),
      repository_id: coordination.fetch(:repository_id),
      base_commit_oid: CandidateAcceptanceWorld::BASE_COMMIT_OID,
      resources: [
        resource_target(
          kind: "file",
          path: coordination.fetch(:path),
          repository_id: coordination.fetch(:repository_id),
          base_blob_oid: CandidateAcceptanceWorld::BASE_BLOB_OID,
          actor_id: coordination.fetch(:agent_id)
        )
      ],
      ttl_seconds: 900
    )
    coordination[:reservation] = task_request("tasks/get", reservation_task_id).dig(
      "result", "result", "structuredContent", "data"
    )
    assert_acceptance(coordination[:reservation], "Impact setup #{prefix} has no reservation result")
  end

  def impact_arguments(candidate, command_id:, actor_id:, surface:)
    candidate_id = candidate.dig(:arguments, :candidate_id)
    events = candidate_events(candidate_id)
    manifest = events.find { _1.type == "CandidateChangeManifestCaptured" }
    build_context = events.find { _1.type == "CandidateBuildContextCaptured" }
    {
      command_id:,
      actor: { kind: "agent", id: actor_id },
      candidate_id:,
      repository_id: candidate.dig(:arguments, :repository_id),
      head_commit_oid: candidate.dig(:arguments, :head_commit_oid),
      manifest_digest: manifest.metadata.fetch("manifest_digest"),
      build_context_digest: build_context&.metadata&.fetch("build_context_digest"),
      analyzer_version: "impact-analyzer-v1",
      surface:
    }.compact
  end

  def surface_from_rows(rows)
    surface = { produces: [], consumes: [], may_affect: [], assumes: [] }
    rows.each do |row|
      direction = row.fetch("direction")
      entry = { impact_key: row.fetch("impact_key") }
      entry[:after] = row.fetch("value") if direction == "produces"
      entry[:value] = row.fetch("value") if direction == "consumes"
      entry[:predicate] = row.fetch("value") if direction == "assumes"
      surface.fetch(direction.to_sym) << entry
    end
    surface
  end

  def submit_impact_task(arguments, execute: true)
    task_id = call_tool("candidate_impact_surface_submit", arguments).dig("result", "taskId")
    assert_acceptance(task_id, "candidate_impact_surface_submit did not return a Task handle")
    execute_task(task_id) if execute
    task_id
  end

  def candidate_impact_view(candidate_id, direction: "outgoing", limit: 20, after_global_position: nil)
    arguments = { candidate_id:, direction:, limit: }
    arguments[:after_global_position] = after_global_position if after_global_position
    call_tool("candidate_impact_get", arguments).dig("result", "structuredContent")
  end

  def project_impact(candidate)
    candidate_id = candidate.dig(:arguments, :candidate_id)
    event = impact_events(candidate).first
    assert_acceptance(event, "Candidate #{candidate_id} has no impact fact")
    await_read_model("Candidate #{candidate_id} impact surface to become available") do
      payload = candidate_impact_view(candidate_id)
      surface = payload.dig("data", "page", "impact_surface")
      [ !surface.nil?, payload ]
    end
  end

  def impact_events(candidate)
    candidate_id = candidate.dig(:arguments, :candidate_id)
    assignment = event_store.read(
      streams.candidate(candidate_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceAssigned" ],
        maximum_count: 1,
        direction: :asc
      )
    ).first
    return [] unless assignment

    event_store.read(
      streams.candidate_impact_surface(assignment.data.fetch("surface_id")),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceDerived" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end
end

World(CandidateImpactAcceptanceWorld)

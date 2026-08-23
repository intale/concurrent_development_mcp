# frozen_string_literal: true

module CandidateAcceptanceWorld
  BASE_COMMIT_OID = "a" * 40
  BASE_BLOB_OID = "c" * 40
  NEW_BLOB_OID = "d" * 40

  def prepare_candidate_coordination(prefix:, agent_id:, path:, project_context: true)
    ids = {
      change_set_id: "CS-CUC-CAN-#{prefix}",
      work_item_id: "W-CUC-CAN-#{prefix}",
      attempt_id: "A-CUC-CAN-#{prefix}"
    }

    complete_candidate_setup_task(
      "change_set_create",
      command_id: "cmd-cuc-can-#{prefix}-create",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      goal: "Coordinate Candidate checkpoint #{prefix}",
      acceptance_criteria: [ "Candidate evidence remains attributable" ]
    )
    complete_candidate_setup_task(
      "work_item_create",
      command_id: "cmd-cuc-can-#{prefix}-work-item",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      repository_id: "billing",
      goal: "Produce Candidate checkpoint #{prefix}",
      acceptance_criteria: [ "The Candidate is durably checkpointed" ]
    )
    complete_candidate_setup_task(
      "change_set_activate",
      command_id: "cmd-cuc-can-#{prefix}-activate",
      actor: { kind: "agent", id: "planner-1" },
      change_set_id: ids.fetch(:change_set_id)
    )
    activation = change_set_events(ids.fetch(:change_set_id)).find do |event|
      event.type == "ChangeSetActivated"
    end
    assert_acceptance(activation, "Candidate setup #{prefix} has no activation fact")
    Coordinator::Container["process_managers.change_set_readiness"].call(activation)

    complete_candidate_setup_task(
      "work_item_acquire",
      command_id: "cmd-cuc-can-#{prefix}-acquire",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [ { repository_id: "billing", commit_oid: BASE_COMMIT_OID } ]
    )
    reservation_task_id = complete_candidate_setup_task(
      "write_set_reserve",
      command_id: "cmd-cuc-can-#{prefix}-reserve",
      actor: { kind: "agent", id: agent_id },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: "billing",
      base_commit_oid: BASE_COMMIT_OID,
      resources: [ { kind: "file", path:, base_blob_oid: BASE_BLOB_OID } ],
      lease_duration_seconds: 900
    )
    reservation = task_request("tasks/get", reservation_task_id).dig(
      "result", "result", "structuredContent", "data"
    )
    assert_acceptance(reservation, "Candidate setup #{prefix} has no reservation result")

    project_attempt_context(**ids) if project_context
    {
      prefix:,
      agent_id:,
      path:,
      ids:,
      reservation:
    }
  end

  def candidate_arguments(
    coordination,
    candidate_id:,
    command_id:,
    head_character:,
    build_context: false
  )
    ids = coordination.fetch(:ids)
    reservation = coordination.fetch(:reservation)
    path = coordination.fetch(:path)
    repository_id = coordination.fetch(:repository_id, "billing")
    arguments = {
      command_id:,
      actor: { kind: "agent", id: coordination.fetch(:agent_id) },
      candidate_id:,
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id:,
      target_branch: "main",
      base_commit_oid: BASE_COMMIT_OID,
      head_commit_oid: head_character * 40,
      checkpoint_kind: "final",
      lease_set_id: reservation.fetch("lease_set_id"),
      leases: reservation.fetch("resources").map do |reference|
        {
          resource_key_hash: reference.fetch("resource_key_hash"),
          lease_id: reference.fetch("lease_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end,
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [ candidate_manifest_file(path) ]
      }
    }
    if build_context
      arguments[:build_context] = {
        collector_version: "build-context-v1",
        inputs: [ { kind: "public_contract", path:, blob_oid: NEW_BLOB_OID } ],
        environment: [ { name: "RUBY_VERSION", value: RUBY_VERSION } ],
        dependency_graph_digest: "sha256:#{'e' * 64}"
      }
    end
    arguments
  end

  def candidate_manifest_file(path)
    {
      status: "modified",
      old_path: path,
      new_path: path,
      old_blob_oid: BASE_BLOB_OID,
      new_blob_oid: NEW_BLOB_OID,
      old_mode: "100644",
      new_mode: "100644"
    }
  end

  def submit_candidate_task(arguments, execute: true)
    task_id = call_tool("candidate_submit", arguments).dig("result", "taskId")
    assert_acceptance(task_id, "candidate_submit did not return a Task handle")
    execute_task(task_id) if execute
    task_id
  end

  def candidate_task_state(task_id)
    task_request("tasks/get", task_id)
  end

  def candidate_events(candidate_id)
    event_store.read(
      streams.candidate(candidate_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          CandidateSubmitted
          CandidateChangeManifestCaptured
          CandidateBuildContextCaptured
          CandidateImpactSurfaceDerived
        ],
        maximum_count: 4,
        direction: :asc
      )
    )
  end

  def candidate_attachment_events(attempt_id)
    event_store.read(
      streams.attempt(attempt_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateAttachedToAttempt" ],
        maximum_count: 20,
        direction: :asc
      )
    )
  end

  def candidate_head_events(repository_id:, head_commit_oid:)
    identity = Coordinator::Write::Candidates::HeadIdentityBuilder.new.call(
      repository_id:,
      object_format: "sha1",
      head_commit_oid:
    )
    event_store.read(
      streams.candidate_head(identity.registry_id),
      Coordinator::Write::EventQueries::CANDIDATE_HEAD_REGISTRATION
    )
  end

  def project_candidate_submission(candidate_id)
    event = candidate_events(candidate_id).find { _1.type == "CandidateSubmitted" }
    assert_acceptance(event, "Candidate #{candidate_id} has no submission fact")
    Coordinator::Container["projectors.candidates_v1"].call(event)
  end

  def project_remaining_candidate_evidence(candidate_id)
    candidate_events(candidate_id).reject { _1.type == "CandidateSubmitted" }.each do |event|
      Coordinator::Container["projectors.candidates_v1"].call(event)
    end
  end

  def project_candidate_attachment(candidate_id, attempt_id)
    event = candidate_attachment_events(attempt_id).find do |candidate_event|
      candidate_event.data.fetch("candidate_id") == candidate_id
    end
    assert_acceptance(event, "Candidate #{candidate_id} has no Attempt attachment")
    Coordinator::Container["projectors.coord_context_v1"].call(event)
  end

  def project_complete_candidate(candidate_id, attempt_id)
    project_candidate_submission(candidate_id)
    project_remaining_candidate_evidence(candidate_id)
    project_candidate_attachment(candidate_id, attempt_id)
  end

  def candidate_view(candidate_id)
    call_tool("candidate_get", { candidate_id: }).dig("result", "structuredContent")
  end

  def candidate_page(attempt_id, limit: 20, after_global_position: nil)
    arguments = { attempt_id:, limit: }
    arguments[:after_global_position] = after_global_position if after_global_position
    call_tool("candidate_list", arguments).dig("result", "structuredContent", "data", "page")
  end

  def candidate_context(attempt_id)
    call_tool("coord_context", { attempt_id: }).dig("result", "structuredContent")
  end

  def assert_candidate_target_absent(candidate_id, arguments, expect_head_absent: true)
    attachments = candidate_attachment_events(arguments.fetch(:attempt_id)).select do |event|
      event.data.fetch("candidate_id") == candidate_id
    end
    assert_acceptance_equal([], candidate_events(candidate_id), "Denied Candidate facts")
    assert_acceptance_equal([], attachments, "Denied Candidate attachments")
    assert_acceptance_equal([], command_events(arguments.fetch(:command_id)), "Denied Candidate completion")
    return unless expect_head_absent

    assert_acceptance_equal(
      [],
      candidate_head_events(
        repository_id: arguments.fetch(:repository_id),
        head_commit_oid: arguments.fetch(:head_commit_oid)
      ),
      "Denied Candidate head facts"
    )
  end

  def complete_candidate_setup_task(tool, **arguments)
    task_id = submit_and_execute(tool, **arguments)
    assert_successful_task(task_id, "Candidate setup #{tool}")
    task_id
  end
end

World(CandidateAcceptanceWorld)

# frozen_string_literal: true

module CoordinationDiscoveryAcceptanceWorld
  DISCOVERY_BASE_COMMIT = "a" * 40
  DISCOVERY_BASE_BLOB = "b" * 40
  DISCOVERY_HEAD_COMMIT = "c" * 40
  DISCOVERY_NEW_BLOB = "d" * 40
  DISCOVERY_REQUIRED_EVIDENCE = %w[combined_tests].freeze

  def prepare_discoverable_coordination(scope:, label:, checkpoint: false, reserve: false)
    repository_id = register_discovery_repository(scope)
    suffix = discovery_suffix(scope, label)
    ids = {
      change_set_id: "CS-DISC-#{suffix}-#{label}",
      work_item_id: "W-DISC-#{suffix}-#{label}",
      attempt_id: "A-DISC-#{suffix}-#{label}"
    }
    discovery_submit(
      "change_set_create",
      client_id: "setup-#{suffix}",
      command_id: "disc.#{suffix}.change-set.create",
      actor: { kind: "agent", id: "planner-#{suffix}" },
      change_set_id: ids.fetch(:change_set_id),
      goal: "Coordinate local label #{label}",
      acceptance_criteria: [ "A clean client can resume through MCP" ]
    )
    discovery_submit(
      "work_item_create",
      client_id: "setup-#{suffix}",
      command_id: "disc.#{suffix}.work-item.create",
      actor: { kind: "agent", id: "planner-#{suffix}" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      repository_id:,
      goal: "Implement local label #{label}",
      acceptance_criteria: [ "The active Attempt is discoverable" ]
    )
    discovery_submit(
      "change_set_activate",
      client_id: "setup-#{suffix}",
      command_id: "disc.#{suffix}.change-set.activate",
      actor: { kind: "agent", id: "planner-#{suffix}" },
      change_set_id: ids.fetch(:change_set_id)
    )
    await_work_item_ready(ids.fetch(:work_item_id))
    discovery_submit(
      "work_item_acquire",
      client_id: "setup-#{suffix}",
      command_id: "disc.#{suffix}.work-item.acquire",
      actor: { kind: "agent", id: "agent-#{suffix}" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      base_snapshots: [ { repository_id:, commit_oid: DISCOVERY_BASE_COMMIT } ]
    )

    coordination = {
      scope:,
      label:,
      suffix:,
      repository_id:,
      ids:
    }
    coordination[:reservation] = reserve_discovery_write_set(coordination) if reserve || checkpoint
    submit_discovery_candidate(coordination) if checkpoint
    await_discoverable_coordination(coordination, candidate_checkpoint_count: checkpoint ? 1 : 0)
    coordination
  end

  def coordination_discovery_payload(scope:, client_id:)
    call_tool("coordination_list", { scope: }, client_id:)
      .dig("result", "structuredContent")
  end

  def coordination_discovery_items(payload)
    payload.dig("data", "page", "items") || []
  end

  def follow_coordination_actions(payload, client_id:)
    actions = payload.fetch("next_actions")
    @coordination_discovery_used_tools ||= []
    actions.filter_map do |action|
      next unless action.fetch("tool") == "coord_context"

      @coordination_discovery_used_tools << action.fetch("tool")
      call_tool(action.fetch("tool"), action.fetch("arguments"), client_id:)
        .dig("result", "structuredContent")
    end
  end

  def submit_discovery_candidate(coordination)
    suffix = coordination.fetch(:suffix)
    ids = coordination.fetch(:ids)
    reservation = coordination.fetch(:reservation)
    path = discovery_path(suffix)
    candidate_id = "CAN-DISC-#{suffix}"
    discovery_submit(
      "candidate_submit",
      client_id: "agent-#{suffix}",
      command_id: "disc.#{suffix}.candidate.submit",
      actor: { kind: "agent", id: "agent-#{suffix}" },
      candidate_id:,
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: coordination.fetch(:repository_id),
      target_branch: "main",
      base_commit_oid: DISCOVERY_BASE_COMMIT,
      head_commit_oid: DISCOVERY_HEAD_COMMIT,
      checkpoint_kind: "intermediate",
      lease_set_id: reservation.fetch("lease_set_id"),
      leases: reservation.fetch("resources").map do |reference|
        {
          resource_id: reference.fetch("resource_id"),
          lease_id: reference.fetch("lease_id"),
          fencing_token: reference.fetch("fencing_token")
        }
      end,
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [
          {
            status: "modified",
            old_path: path,
            new_path: path,
            old_blob_oid: DISCOVERY_BASE_BLOB,
            new_blob_oid: DISCOVERY_NEW_BLOB,
            old_mode: "100644",
            new_mode: "100644"
          }
        ]
      }
    )
    coordination[:candidate_id] = candidate_id
  end

  def activate_discovery_impact_policy(coordination)
    suffix = coordination.fetch(:suffix)
    ids = coordination.fetch(:ids)
    message_id = "M-DISC-#{suffix}"
    interpretation_id = "I-DISC-#{suffix}"
    decision_id = "D-DISC-#{suffix}"
    client_id = "policy-#{suffix}"
    tasks = []
    tasks << discovery_submit(
      "guidance_record",
      client_id:,
      command_id: "disc.#{suffix}.guidance.record",
      actor: { kind: "user", id: "user-label" },
      message_id:,
      conversation_id: "C-DISC-#{suffix}",
      source: "mcp_client",
      text: "Require combined tests for Candidate impact.",
      anchors: {
        repository_ids: [],
        change_set_id: ids.fetch(:change_set_id),
        work_item_id: nil,
        attempt_id: nil
      }
    )
    tasks << discovery_submit(
      "decision_interpretation_propose",
      client_id:,
      command_id: "disc.#{suffix}.interpretation.propose",
      actor: { kind: "agent", id: "classifier-#{suffix}" },
      interpretation_id:,
      source_message_id: message_id,
      source_span: nil,
      classifier: {
        id: "classifier-#{suffix}",
        version: "decision-classifier-v1",
        ontology_version: 1,
        confidence_millionths: 950_000
      },
      proposed_decision: discovery_impact_policy_definition(ids.fetch(:change_set_id)),
      ambiguities: []
    )
    tasks << discovery_submit(
      "decision_interpretation_adjudicate",
      client_id:,
      command_id: "disc.#{suffix}.interpretation.accept",
      actor: { kind: "orchestrator", id: "guidance-host" },
      source_message_id: message_id,
      interpretation_id:,
      action: "accept",
      rationale: {
        code: "user_confirmed",
        summary: "The Candidate impact policy matches the user instruction."
      },
      clarification: nil
    )
    tasks << discovery_submit(
      "decision_activate",
      client_id:,
      command_id: "disc.#{suffix}.decision.activate",
      actor: { kind: "orchestrator", id: "guidance-host" },
      decision_id:,
      interpretation_id:,
      rationale: {
        code: "user_confirmed",
        summary: "Activate the accepted Candidate impact policy."
      }
    )
    assert_acceptance_equal(4, tasks.length, "Decision setup Task count")
    coordination[:decision_id] = decision_id
    await_discovery_decision(coordination)
    decision_id
  end

  def discovery_decision_context(coordination)
    ids = coordination.fetch(:ids)
    {
      workspace_id: nil,
      repository_id: coordination.fetch(:repository_id),
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      phase: "implementation",
      language: "ruby",
      paths: [ discovery_path(coordination.fetch(:suffix)) ],
      environment: nil,
      agent_role: "implementer"
    }
  end

  private

  def register_discovery_repository(scope)
    @discovery_repositories ||= {}
    return @discovery_repositories.fetch(scope) if @discovery_repositories.key?(scope)

    repository_id = discovery_repository_id(scope)
    suffix = discovery_suffix(scope, "repository")
    discovery_submit(
      "repository_register",
      client_id: "repository-#{suffix}",
      command_id: "disc.#{suffix}.repository.register",
      actor: { kind: "agent", id: "repository-registrar" },
      repository_id:,
      scope:,
      repository_key: "repository-#{suffix}",
      display_name: "Discovery repository #{suffix}",
      paths: [],
      remotes: []
    )
    await_read_model("Repository #{repository_id} to become available for exact scope #{scope}") do
      payload = call_tool(
        "repository_list",
        { scope:, repository_key: "repository-#{suffix}", limit: 20 },
        client_id: "repository-#{suffix}"
      ).dig("result", "structuredContent")
      items = payload.dig("data", "page", "items") || []
      [ items.any? { _1.fetch("repository_id") == repository_id }, payload ]
    end
    @discovery_repositories[scope] = repository_id
  end

  def reserve_discovery_write_set(coordination)
    suffix = coordination.fetch(:suffix)
    ids = coordination.fetch(:ids)
    state = discovery_submit(
      "write_set_reserve",
      client_id: "agent-#{suffix}",
      command_id: "disc.#{suffix}.write-set.reserve",
      actor: { kind: "agent", id: "agent-#{suffix}" },
      change_set_id: ids.fetch(:change_set_id),
      work_item_id: ids.fetch(:work_item_id),
      attempt_id: ids.fetch(:attempt_id),
      repository_id: coordination.fetch(:repository_id),
      base_commit_oid: DISCOVERY_BASE_COMMIT,
      resources: [
        resource_target(
          kind: "file",
          path: discovery_path(suffix),
          repository_id: coordination.fetch(:repository_id),
          base_blob_oid: DISCOVERY_BASE_BLOB,
          client_id: "agent-#{suffix}"
        )
      ],
      lease_duration_seconds: 900
    )
    state.dig("result", "result", "structuredContent", "data")
  end

  def await_discoverable_coordination(coordination, candidate_checkpoint_count:)
    await_read_model("Coordination #{coordination.dig(:ids, :change_set_id)} to become discoverable") do
      payload = coordination_discovery_payload(
        scope: coordination.fetch(:scope),
        client_id: "setup-#{coordination.fetch(:suffix)}"
      )
      item = coordination_discovery_items(payload).find do |candidate|
        candidate.fetch("change_set_id") == coordination.dig(:ids, :change_set_id)
      end
      matched = item &&
                item.fetch("active_attempt_ids").include?(coordination.dig(:ids, :attempt_id)) &&
                item.fetch("candidate_checkpoint_count") == candidate_checkpoint_count
      [ matched, payload ]
    end
  end

  def await_discovery_decision(coordination)
    await_read_model("Decision #{coordination.fetch(:decision_id)} to become discoverable") do
      payload = call_tool(
        "decision_list",
        {
          repository_id: coordination.fetch(:repository_id),
          topic_id: "candidate.impact_policy",
          policy_status: "active"
        },
        client_id: "policy-#{coordination.fetch(:suffix)}"
      ).dig("result", "structuredContent")
      ids = (payload.dig("data", "page", "items") || []).map { _1.fetch("decision_id") }
      [ ids.include?(coordination.fetch(:decision_id)), payload ]
    end
  end

  def discovery_submit(tool, client_id:, **arguments)
    task_id = submit_and_execute(tool, client_id:, **arguments)
    state = task_request("tasks/get", task_id, client_id:)
    assert_acceptance_equal("completed", state.dig("result", "status"), "#{tool} Task status")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "#{tool} Task result")
    state
  end

  def discovery_repository_id(scope)
    digest = Coordinator::Shared::CanonicalJson.new.sha256(
      { "coordination_discovery_scope" => scope }
    ).delete_prefix("sha256:")
    "01a04733-#{digest[0, 4]}-7#{digest[4, 3]}-8#{digest[7, 3]}-#{digest[10, 12]}"
  end

  def discovery_suffix(scope, label)
    Coordinator::Shared::CanonicalJson.new.sha256(
      { "scope" => scope, "label" => label }
    ).delete_prefix("sha256:")[0, 10]
  end

  def discovery_path(suffix)
    "app/discovery/#{suffix}.rb"
  end

  def discovery_impact_policy_definition(change_set_id)
    {
      statement_kind: "directive",
      topic_id: "candidate.impact_policy",
      effect: "require",
      modality: "must",
      value: {
        schema: "string-set/v1",
        name: nil,
        items: DISCOVERY_REQUIRED_EVIDENCE,
        target_kind: nil,
        target_id: nil,
        action: nil
      },
      scope: {
        workspace_id: nil,
        repository_ids: [],
        branch_selectors: [],
        change_set_id:,
        work_item_id: nil,
        attempt_id: nil,
        candidate_id: nil,
        path_selectors: [],
        symbol_selectors: [],
        contract_selectors: [],
        schema_selectors: [],
        environments: [],
        agent_roles: []
      },
      conditions: {
        phases: [],
        languages: [],
        tags: [],
        repository_kinds: [],
        artifact_kinds: [],
        environments: []
      },
      validity: { valid_from: nil, valid_until: nil, until_event: nil },
      authority: { actor_id: "user-label", role: "project-owner" },
      enforcement: {
        level: "advisory",
        retroactivity: "all_unmerged_candidates",
        on_violation: "warn"
      },
      relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
    }
  end
end

World(CoordinationDiscoveryAcceptanceWorld)

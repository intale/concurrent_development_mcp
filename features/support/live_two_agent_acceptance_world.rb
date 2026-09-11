# frozen_string_literal: true

module LiveTwoAgentAcceptanceWorld
  ReportedErrorCollector = Data.define(:errors) do
    def report(error, **)
      errors << error
    end
  end

  BASE_COMMIT = "a" * 40
  BASE_BLOB = "b" * 40
  CANDIDATE_HEADS = {
    agent_a: "c" * 40,
    agent_b: "d" * 40,
    integration: "e" * 40
  }.freeze
  NEW_BLOBS = {
    agent_a: "3" * 40,
    agent_b: "4" * 40,
    integration: "5" * 40
  }.freeze
  MERGE_COMMITS = {
    primary: "1" * 40,
    secondary: "2" * 40
  }.freeze
  CLIENTS = {
    agent_a: "luna-5.6-a",
    agent_b: "luna-5.6-b",
    replacement: "luna-5.6-replacement",
    verifier: "luna-external-verifier"
  }.freeze

  def prepare_live_two_luna_project(scope)
    @luna_scope = scope
    @luna_change_set_id = "CS-TWO-LUNA-LIVE-01"
    @luna_repository_ids = {
      primary: RepositoryScenario.repository_id("two-luna-live-primary"),
      secondary: RepositoryScenario.repository_id("two-luna-live-secondary")
    }.freeze
    @luna_participants = {
      agent_a: participant(
        client_id: CLIENTS.fetch(:agent_a),
        work_item_id: "WI-TWO-LUNA-A",
        attempt_id: "ATT-TWO-LUNA-A",
        repository: :primary
      ),
      agent_b: participant(
        client_id: CLIENTS.fetch(:agent_b),
        work_item_id: "WI-TWO-LUNA-B",
        attempt_id: "ATT-TWO-LUNA-B",
        repository: :primary
      ),
      integration: participant(
        client_id: CLIENTS.fetch(:agent_b),
        work_item_id: "WI-TWO-LUNA-INTEGRATION",
        attempt_id: "ATT-TWO-LUNA-INTEGRATION",
        repository: :secondary
      )
    }.freeze
    prepare_mcp_clients(*CLIENTS.values)
    start_live_subscriptions

    register_luna_repositories
    create_luna_change_set
    await_luna_work_items(status: "ready")
  end

  def discover_and_acquire_luna_work
    @luna_initial_discoveries = CLIENTS.values_at(:agent_a, :agent_b).to_h do |client_id|
      discovery = luna_query(
        "coordination_list",
        { scope: @luna_scope, statuses: [ "active" ], limit: 20 },
        client_id:
      )
      item = discovery.dig("data", "page", "items").find do
        _1.fetch("change_set_id") == @luna_change_set_id
      end
      assert_acceptance(item, "#{client_id} did not discover the active ChangeSet from scope")
      action = discovery.fetch("next_actions").find do
        _1.fetch("tool") == "coord_context" &&
          _1.dig("arguments", "change_set_id") == @luna_change_set_id
      end
      assert_acceptance(action, "#{client_id} received no executable coord_context action")
      context = luna_query(action.fetch("tool"), action.fetch("arguments"), client_id:)
      [ client_id, { discovery:, context: } ]
    end

    @luna_participants.each_value do |entry|
      luna_successful_task(
        "work_item_acquire",
        {
          command_id: "two-luna.acquire.#{entry.fetch(:attempt_id).downcase}",
          actor: luna_actor(entry),
          change_set_id: @luna_change_set_id,
          work_item_id: entry.fetch(:work_item_id),
          attempt_id: entry.fetch(:attempt_id),
          base_snapshots: [
            {
              repository_id: entry.fetch(:repository_id),
              commit_oid: BASE_COMMIT
            }
          ]
        },
        client_id: entry.fetch(:client_id)
      )
    end
    await_luna_attempts
  end

  def contend_for_luna_parent_and_child
    agent_a = @luna_participants.fetch(:agent_a)
    agent_b = @luna_participants.fetch(:agent_b)
    @luna_reservations = {
      integration: reserve_luna_disjoint_resource(
        :integration,
        { kind: "file", path: "lib/integration_adapter.rb", base_blob_oid: BASE_BLOB }
      )
    }
    requests = {
      agent_a: [
        agent_a,
        {
          kind: "directory",
          path: "app/models",
          mode: "exclusive",
          purpose: "Restructure the model layer",
          context: "Child edits would be invalidated by the restructuring."
        }
      ],
      agent_b: [
        agent_b,
        {
          kind: "file",
          path: "app/models/order.rb",
          base_blob_oid: BASE_BLOB,
          mode: "shared",
          purpose: "Adjust the order model"
        }
      ]
    }.transform_values do |entry, resource|
      [ entry, luna_resource_target(entry, resource) ]
    end
    participants_by_client = requests.to_h do |key, (entry, resource)|
      [ entry.fetch(:client_id), [ key, entry, resource ] ]
    end
    candidates = submit_tasks_in_distinct_execution_lanes(
      client_ids: participants_by_client.keys
    ) do |client_id, round|
      key, entry, resource = participants_by_client.fetch(client_id)
      command_id = "two-luna.reserve.overlap.#{key}.#{round}"
      luna_task_handle(
        "write_set_reserve",
        reservation_arguments(entry, command_id:, resources: [ resource ]),
        client_id:
      ).merge(key:, command_id:)
    end
    @luna_contention_command_ids = candidates.to_h do
      [ _1.fetch(:key), _1.fetch(:internal_command_id) ]
    end.freeze
    @luna_contention_handles = candidates.to_h do
      [ _1.fetch(:key), _1.except(:key, :command_id, :internal_command_id, :worker_lane) ]
    end
    install_contention_barrier(
      operation: "coordination_task_execute",
      command_ids: @luna_contention_command_ids.values
    )
    start_process_subscriptions
    await_contention_evidence

    release_contention_command(@luna_contention_command_ids.fetch(:agent_a))
    await_contention_command_completion(@luna_contention_command_ids.fetch(:agent_a))
    release_contention_command(@luna_contention_command_ids.fetch(:agent_b))
    @luna_contention_results = @luna_contention_handles.transform_values do |handle|
      luna_task_result(handle)
    end
    @luna_reservations[:agent_a] = @luna_contention_results.fetch(:agent_a).fetch("data")

    @luna_reservations[:agent_b] = reserve_luna_disjoint_resource(
      :agent_b,
      { kind: "file", path: "spec/services/payment_spec.rb", base_blob_oid: BASE_BLOB }
    )
  end

  def assert_luna_contention_contract
    assert_acceptance_equal(2, @contention_evidence.length, "Contention arrivals")
    assert_acceptance_equal(
      @luna_contention_command_ids.values.sort,
      @contention_evidence.map { _1.fetch(:command_id) }.sort,
      "Contending commands"
    )
    assert_acceptance_equal(
      [ 0, 1 ],
      @contention_evidence.map { _1.fetch(:worker_lane) }.sort,
      "Task execution lanes"
    )
    assert_acceptance_equal(
      2,
      @contention_evidence.map { _1.fetch(:thread_id) }.uniq.length,
      "Task executor threads"
    )
    assert_acceptance_equal(
      "ok",
      @luna_contention_results.dig(:agent_a, "status"),
      "Parent reservation"
    )
    denied = @luna_contention_results.fetch(:agent_b)
    assert_acceptance_equal("busy", denied.fetch("status"), "Child reservation")
    blocker = denied.dig("data", "details", "blockers").sole
    assert_acceptance_equal(
      CLIENTS.fetch(:agent_a),
      blocker.fetch("owner_agent_id"),
      "Blocking agent"
    )
    assert_acceptance_equal("exclusive", blocker.fetch("mode"), "Blocking mode")
    assert_acceptance_equal("Restructure the model layer", blocker.fetch("purpose"), "Blocking purpose")
    assert_acceptance(
      blocker.fetch("expires_at"),
      "The busy result must expose when the blocking intention elapses"
    )
    assert_acceptance_equal(3, @luna_reservations.length, "Active disjoint write sets")
  end

  def checkpoint_luna_candidates
    manifests = {
      agent_a: [ "app/models/order.rb", NEW_BLOBS.fetch(:agent_a) ],
      agent_b: [ "spec/services/payment_spec.rb", NEW_BLOBS.fetch(:agent_b) ],
      integration: [ "lib/integration_adapter.rb", NEW_BLOBS.fetch(:integration) ]
    }
    @luna_candidates = manifests.to_h do |key, (path, new_blob_oid)|
      entry = @luna_participants.fetch(key)
      reservation = @luna_reservations.fetch(key)
      candidate_id = "CAN-TWO-LUNA-#{key.to_s.upcase.tr('_', '-')}"
      content = luna_successful_task(
        "candidate_submit",
        {
          command_id: "two-luna.candidate.#{key}",
          actor: luna_actor(entry),
          candidate_id:,
          change_set_id: @luna_change_set_id,
          work_item_id: entry.fetch(:work_item_id),
          attempt_id: entry.fetch(:attempt_id),
          repository_id: entry.fetch(:repository_id),
          target_branch: "main",
          base_commit_oid: BASE_COMMIT,
          head_commit_oid: CANDIDATE_HEADS.fetch(key),
          checkpoint_kind: "final",
          lease_set_id: reservation.fetch("lease_set_id"),
          leases: luna_lease_references(reservation),
          change_manifest: {
            collector_version: "git-evidence-v1",
            files: [
              {
                status: "modified",
                old_path: path,
                new_path: path,
                old_blob_oid: BASE_BLOB,
                new_blob_oid:,
                old_mode: "100644",
                new_mode: "100644"
              }
            ]
          }
        },
        client_id: entry.fetch(:client_id)
      )
      [ key, content.fetch("data") ]
    end

    await_luna_context("three final Candidate checkpoints") do |context|
      context.fetch("candidate_checkpoints").length == 3
    end
  end

  def demonstrate_luna_ap_lag_and_complete_work
    agent_a = @luna_participants.fetch(:agent_a)
    before = luna_query(
      "coord_context",
      { change_set_id: @luna_change_set_id },
      client_id: agent_a.fetch(:client_id)
    )
    before_attempt = luna_attempt(before, agent_a.fetch(:attempt_id))
    assert_acceptance(before_attempt.dig("write_set", "released_at").nil?, "Agent A lease is already released")

    stop_read_model_subscriptions
    release_luna_write_set(:agent_a)
    stale = luna_query(
      "coord_context",
      { change_set_id: @luna_change_set_id },
      client_id: agent_a.fetch(:client_id)
    )
    stale_attempt = luna_attempt(stale, agent_a.fetch(:attempt_id))
    assert_acceptance_equal("ok", stale.fetch("status"), "Available stale read model")
    assert_acceptance_equal(before.fetch("context_token"), stale.fetch("context_token"), "Stale context token")
    assert_acceptance(stale_attempt.dig("write_set", "released_at").nil?, "Read side advanced while stopped")
    assert_acceptance(
      (stale.keys & %w[fresh pending projection_status stream_revision]).empty?,
      "The stale response exposed a freshness availability gate"
    )

    renewal = luna_task(
      "lease_renew",
      {
        command_id: "two-luna.lease.renew-from-stale-view",
        actor: luna_actor(agent_a),
        change_set_id: @luna_change_set_id,
        work_item_id: agent_a.fetch(:work_item_id),
        attempt_id: agent_a.fetch(:attempt_id),
        lease_set_id: @luna_reservations.dig(:agent_a, "lease_set_id"),
        leases: luna_lease_references(@luna_reservations.fetch(:agent_a)),
        lease_duration_seconds: 600
      },
      client_id: agent_a.fetch(:client_id)
    )
    assert_acceptance_equal("denied", renewal.fetch("status"), "Authoritative stale-command status")
    assert_acceptance(
      renewal.dig("data", "code").to_s.length.positive?,
      "Authoritative stale-command rejection must expose a typed reason"
    )
    @luna_lag_observation = { before:, stale:, renewal: }

    restart_read_model_subscriptions
    await_luna_context("Agent A release to converge") do |context|
      attempt = context.fetch("attempts").find do
        _1.fetch("attempt_id") == agent_a.fetch(:attempt_id)
      end
      !attempt.dig("write_set", "released_at").nil?
    end
    release_luna_write_set(:agent_b)
    release_luna_write_set(:integration)

    @luna_participants.each do |key, entry|
      luna_successful_task(
        "work_item_complete",
        {
          command_id: "two-luna.work-item.complete.#{key}",
          actor: luna_actor(entry),
          change_set_id: @luna_change_set_id,
          work_item_id: entry.fetch(:work_item_id),
          attempt_id: entry.fetch(:attempt_id),
          candidate_id: @luna_candidates.dig(key, "candidate_id"),
          produced_outputs: []
        },
        client_id: entry.fetch(:client_id)
      )
    end
    await_luna_work_items(status: "completed")
  end

  def persist_luna_decision_and_skill
    publish_luna_skill
    record_luna_decision
  end

  def integrate_and_release_luna_change_set
    primary_candidates = %i[agent_a agent_b].map do |key|
      candidate = @luna_candidates.fetch(key)
      { candidate_id: candidate.fetch("candidate_id"), head_commit_oid: candidate.fetch("head_commit_oid") }
    end
    secondary_candidate = @luna_candidates.fetch(:integration)
    @luna_merge_members = [
      build_luna_merge_member(
        key: :primary,
        candidates: primary_candidates,
        merge_commit_oid: MERGE_COMMITS.fetch(:primary),
        index: 1
      ),
      build_luna_merge_member(
        key: :secondary,
        candidates: [
          {
            candidate_id: secondary_candidate.fetch("candidate_id"),
            head_commit_oid: secondary_candidate.fetch("head_commit_oid")
          }
        ],
        merge_commit_oid: MERGE_COMMITS.fetch(:secondary),
        index: 2
      )
    ]
    @luna_release_set_id = "REL-TWO-LUNA-LIVE-01"
    luna_successful_task(
      "release_set_prepare",
      {
        command_id: "two-luna.release.prepare",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        release_set_id: @luna_release_set_id,
        ordered_members: @luna_merge_members.map { _1.fetch(:release_member) }
      },
      client_id: CLIENTS.fetch(:verifier)
    )

    integrations = @luna_merge_members.map.with_index(1) do |member, index|
      record_luna_merge_observation_and_integration(member, index:)
    end
    verification = luna_successful_task(
      "release_verification_record",
      {
        command_id: "two-luna.release.verify",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        release_set_id: @luna_release_set_id,
        integration_events: integrations.map { _1.fetch("integration_event") },
        evidence: {
          producer: { name: "two-luna-composite-suite", version: "1.0.0" },
          run_id: "two-luna-release-verification",
          environment_digest: "sha256:#{'6' * 64}",
          result_digest: "sha256:#{'7' * 64}",
          outcome: "passed",
          findings: [],
          produced_at: "2026-08-28T10:30:00.000000Z"
        }
      },
      client_id: CLIENTS.fetch(:verifier)
    ).fetch("data")
    luna_successful_task(
      "release_activation_record",
      {
        command_id: "two-luna.release.activate",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        release_set_id: @luna_release_set_id,
        verification_event: verification.fetch("verification_event"),
        verification_digest: verification.fetch("verification_digest"),
        activation_point: {
          kind: "deployment_manifest",
          environment: "acceptance",
          external_reference: "two-luna/releases/1",
          state_digest: "sha256:#{'8' * 64}",
          producer: { name: "two-luna-release-adapter", version: "1.0.0" },
          run_id: "two-luna-release-activation"
        }
      },
      client_id: CLIENTS.fetch(:verifier)
    )
    @luna_release_view = await_read_model("ReleaseSet #{@luna_release_set_id} completion") do
      payload = luna_query(
        "release_set_get",
        { release_set_id: @luna_release_set_id },
        client_id: CLIENTS.fetch(:verifier)
      )
      [ payload.dig("data", "release_set", "status") == "completed", payload ]
    end
    await_luna_context("ChangeSet completion after ReleaseSet completion") do |context|
      context.dig("change_set", "status") == "completed"
    end
    capture_luna_release_index
  end

  def assert_luna_release_completed_through_live_saga
    release_set = @luna_release_view.dig("data", "release_set")
    assert_acceptance_equal("completed", release_set.fetch("status"), "ReleaseSet status")
    assert_acceptance_equal("activated", release_set.dig("completion", "outcome"), "ReleaseSet outcome")
    process_set = @live_subscription_sets.fetch(:process_managers)
    assert_acceptance(
      process_set.processed_event_count("release-set-lifecycle-v1").positive?,
      "The live ReleaseSet lifecycle subscription processed no facts"
    )
  end

  def reconstruct_luna_project_from_scope
    client_id = CLIENTS.fetch(:replacement)
    discovery = luna_query(
      "coordination_list",
      { scope: @luna_scope, statuses: %w[planning active completed], limit: 20 },
      client_id:
    )
    summary = discovery.dig("data", "page", "items").find do
      _1.fetch("change_set_id") == @luna_change_set_id
    end
    assert_acceptance(summary, "Replacement client did not discover the ChangeSet")
    action = discovery.fetch("next_actions").find do
      _1.dig("arguments", "change_set_id") == summary.fetch("change_set_id")
    end
    context = luna_query(action.fetch("tool"), action.fetch("arguments"), client_id:)

    decisions = summary.fetch("repository_ids").flat_map do |repository_id|
      luna_query(
        "decision_list",
        {
          repository_id:,
          topic_id: "testing.framework",
          policy_status: "active",
          limit: 20
        },
        client_id:
      ).dig("data", "page", "items")
    end.uniq { _1.fetch("decision_id") }
    skills = luna_query(
      "skill_list",
      { name: "checkpointed-coordination", scope: @luna_scope, limit: 20 },
      client_id:
    ).dig("data", "page", "items")
    artifacts = luna_query(
      "development_artifact_list",
      { scope: @luna_scope, labels: [ "release-index" ], limit: 20 },
      client_id:
    ).dig("data", "page", "items")
    artifact = artifacts.sole
    artifact_content = luna_query(
      "development_artifact_content_get",
      { artifact_id: artifact.fetch("artifact_id") },
      client_id:
    )
    release_index = JSON.parse(artifact_content.dig("data", "content", "text"))
    release = luna_query(
      "release_set_get",
      { release_set_id: release_index.fetch("release_set_id") },
      client_id:
    )
    @luna_reconstruction = luna_round_trip(
      discovery:,
      summary:,
      context:,
      decisions:,
      skills:,
      artifacts:,
      release:
    )
  end

  def assert_complete_luna_reconstruction
    reconstruction = @luna_reconstruction
    context = reconstruction.dig("context", "data", "context")
    assert_acceptance_equal("completed", reconstruction.dig("summary", "status"), "Discovered ChangeSet")
    assert_acceptance_equal(3, context.fetch("attempts").length, "Attempt history")
    assert_acceptance_equal(3, context.fetch("candidate_checkpoints").length, "Candidate checkpoints")
    assert_acceptance_equal(
      @luna_decision_id,
      reconstruction.fetch("decisions").sole.fetch("decision_id"),
      "Active Decision"
    )
    assert_acceptance_equal(1, reconstruction.fetch("skills").sole.fetch("revision"), "Skill revision")
    assert_acceptance_equal(1, reconstruction.fetch("artifacts").length, "Release-index Artifact")
    assert_acceptance_equal(
      "completed",
      reconstruction.dig("release", "data", "release_set", "status"),
      "Reconstructed ReleaseSet"
    )
    release_members = reconstruction.dig("release", "data", "release_set", "ordered_members")
    assert_acceptance_equal(
      @luna_candidates.values.map { _1.fetch("candidate_id") }.sort,
      release_members.flat_map { _1.fetch("ordered_candidate_ids") }.sort,
      "Reconstructed ReleaseSet Candidate coverage"
    )
  end

  private

  def participant(client_id:, work_item_id:, attempt_id:, repository:)
    {
      client_id:,
      agent_id: client_id,
      work_item_id:,
      attempt_id:,
      repository_id: @luna_repository_ids.fetch(repository)
    }.freeze
  end

  def register_luna_repositories
    @luna_repository_ids.each_with_index do |(key, repository_id), index|
      luna_successful_task(
        "repository_register",
        {
          command_id: "two-luna.repository.register.#{key}",
          actor: { kind: "agent", id: "luna-project-bootstrap" },
          repository_id:,
          scope: @luna_scope,
          repository_key: key.to_s,
          display_name: "Two Luna #{key} repository",
          paths: [],
          remotes: []
        },
        client_id: CLIENTS.values_at(:agent_a, :agent_b).fetch(index)
      )
    end
    await_read_model("both project repositories to become discoverable") do
      payload = luna_query(
        "repository_list",
        { scope: @luna_scope, limit: 20 },
        client_id: CLIENTS.fetch(:agent_a)
      )
      ids = payload.dig("data", "page", "items").map { _1.fetch("repository_id") }
      [ (@luna_repository_ids.values - ids).empty?, payload ]
    end
  end

  def create_luna_change_set
    planner = { kind: "agent", id: "luna-project-bootstrap" }
    luna_successful_task(
      "change_set_create",
      {
        command_id: "two-luna.change-set.create",
        actor: planner,
        change_set_id: @luna_change_set_id,
        goal: "Coordinate checkpointed concurrent changes across two repositories",
        acceptance_criteria: [
          "Overlapping resources serialize",
          "Disjoint resources remain available",
          "The cross-repository release completes"
        ]
      },
      client_id: CLIENTS.fetch(:agent_a)
    )
    @luna_participants.each do |key, entry|
      luna_successful_task(
        "work_item_create",
        {
          command_id: "two-luna.work-item.create.#{key}",
          actor: planner,
          change_set_id: @luna_change_set_id,
          work_item_id: entry.fetch(:work_item_id),
          repository_id: entry.fetch(:repository_id),
          goal: "Implement #{key} coordination slice",
          acceptance_criteria: [ "A final Candidate checkpoint is mergeable" ]
        },
        client_id: CLIENTS.fetch(:agent_a)
      )
    end
    luna_successful_task(
      "change_set_activate",
      {
        command_id: "two-luna.change-set.activate",
        actor: planner,
        change_set_id: @luna_change_set_id
      },
      client_id: CLIENTS.fetch(:agent_a)
    )
  end

  def await_luna_work_items(status:)
    await_luna_context("all WorkItems to become #{status}") do |context|
      items = context.fetch("work_items")
      items.length == @luna_participants.length && items.all? { _1.fetch("status") == status }
    end
  end

  def await_luna_attempts
    await_luna_context("all Attempts to become available") do |context|
      ids = context.fetch("attempts").map { _1.fetch("attempt_id") }
      (@luna_participants.values.map { _1.fetch(:attempt_id) } - ids).empty?
    end
  end

  def await_luna_context(label)
    await_read_model(label) do
      payload = luna_query(
        "coord_context",
        { change_set_id: @luna_change_set_id },
        client_id: CLIENTS.fetch(:agent_a)
      )
      context = payload.dig("data", "context")
      [ context && yield(context), payload ]
    end
  end

  def reservation_arguments(entry, command_id:, resources:)
    {
      command_id:,
      actor: luna_actor(entry),
      change_set_id: @luna_change_set_id,
      work_item_id: entry.fetch(:work_item_id),
      attempt_id: entry.fetch(:attempt_id),
      repository_id: entry.fetch(:repository_id),
      base_commit_oid: BASE_COMMIT,
      resources:,
      lease_duration_seconds: 600
    }
  end

  def reserve_luna_disjoint_resource(key, resource)
    entry = @luna_participants.fetch(key)
    luna_successful_task(
      "write_set_reserve",
      reservation_arguments(
        entry,
        command_id: "two-luna.reserve.disjoint.#{key}",
        resources: [ luna_resource_target(entry, resource) ]
      ),
      client_id: entry.fetch(:client_id)
    ).fetch("data")
  end

  def release_luna_write_set(key)
    entry = @luna_participants.fetch(key)
    reservation = @luna_reservations.fetch(key)
    luna_successful_task(
      "lease_release",
      {
        command_id: "two-luna.lease.release.#{key}",
        actor: luna_actor(entry),
        change_set_id: @luna_change_set_id,
        work_item_id: entry.fetch(:work_item_id),
        attempt_id: entry.fetch(:attempt_id),
        lease_set_id: reservation.fetch("lease_set_id"),
        leases: luna_lease_references(reservation)
      },
      client_id: entry.fetch(:client_id)
    )
  end

  def luna_lease_references(reservation)
    reservation.fetch("resources").map do |resource|
      resource.slice("resource_id", "lease_id", "fencing_token")
    end
  end

  def luna_resource_target(entry, resource)
    resource_target(
      kind: resource.fetch(:kind),
      path: resource.fetch(:path),
      repository_id: entry.fetch(:repository_id),
      base_blob_oid: resource[:base_blob_oid],
      mode: resource[:mode],
      purpose: resource[:purpose],
      context: resource[:context],
      client_id: entry.fetch(:client_id),
      actor_id: entry.fetch(:agent_id)
    )
  end

  def luna_attempt(payload, attempt_id)
    payload.dig("data", "context", "attempts").find do
      _1.fetch("attempt_id") == attempt_id
    end
  end

  def luna_actor(entry)
    { kind: "agent", id: entry.fetch(:agent_id) }
  end

  def publish_luna_skill
    content = luna_successful_task(
      "skill_publish",
      {
        command_id: "two-luna.skill.publish",
        actor: { kind: "agent", id: CLIENTS.fetch(:agent_a) },
        name: "checkpointed-coordination",
        scope: @luna_scope,
        expected_revision: 0,
        description: "Coordinate checkpointed concurrent development through MCP",
        instructions: "Discover scope, acquire a WorkItem, reserve the narrowest write set, and checkpoint a Candidate.",
        assets: [
          {
            path: "examples/checkpoint.txt",
            executable: false,
            content: {
              encoding: "utf-8",
              media_type: "text/plain",
              text: "checkpoint through MCP\n"
            }
          }
        ]
      },
      client_id: CLIENTS.fetch(:agent_a)
    )
    assert_acceptance_equal(1, content.dig("data", "revision"), "Published Skill revision")
    await_read_model("project Skill to become discoverable") do
      payload = luna_query(
        "skill_list",
        { name: "checkpointed-coordination", scope: @luna_scope, limit: 20 },
        client_id: CLIENTS.fetch(:agent_b)
      )
      items = payload.dig("data", "page", "items")
      [ items.any? { _1.fetch("revision") == 1 }, payload ]
    end
  end

  def record_luna_decision
    message_id = "MSG-TWO-LUNA-TESTING"
    interpretation_id = "INT-TWO-LUNA-TESTING"
    @luna_decision_id = "DEC-TWO-LUNA-TESTING"
    tasks = [
      [
        "guidance_record",
        {
          command_id: "two-luna.guidance.record",
          actor: { kind: "user", id: "two-luna-user" },
          message_id:,
          conversation_id: "CONV-TWO-LUNA",
          source: "mcp_client",
          text: "Use RSpec for this coordinated project.",
          anchors: {
            repository_ids: [ @luna_repository_ids.fetch(:primary) ],
            change_set_id: @luna_change_set_id,
            work_item_id: nil,
            attempt_id: nil
          }
        }
      ],
      [
        "decision_interpretation_propose",
        {
          command_id: "two-luna.decision.propose",
          actor: { kind: "agent", id: CLIENTS.fetch(:agent_b) },
          interpretation_id:,
          source_message_id: message_id,
          source_span: nil,
          classifier: {
            id: "two-luna-classifier",
            version: "decision-classifier-v1",
            ontology_version: 1,
            confidence_millionths: 980_000
          },
          proposed_decision: luna_testing_decision,
          ambiguities: []
        }
      ],
      [
        "decision_interpretation_adjudicate",
        {
          command_id: "two-luna.decision.accept",
          actor: { kind: "orchestrator", id: "two-luna-host" },
          source_message_id: message_id,
          interpretation_id:,
          action: "accept",
          rationale: { code: "user_confirmed", summary: "The reading matches the user instruction." },
          clarification: nil
        }
      ],
      [
        "decision_activate",
        {
          command_id: "two-luna.decision.activate",
          actor: { kind: "orchestrator", id: "two-luna-host" },
          decision_id: @luna_decision_id,
          interpretation_id:,
          rationale: { code: "user_confirmed", summary: "Activate the accepted project Decision." }
        }
      ]
    ]
    tasks.each do |tool, arguments|
      luna_successful_task(tool, arguments, client_id: CLIENTS.fetch(:agent_b))
    end
    await_read_model("project Decision to become discoverable") do
      payload = luna_query(
        "decision_list",
        {
          repository_id: @luna_repository_ids.fetch(:primary),
          topic_id: "testing.framework",
          policy_status: "active",
          limit: 20
        },
        client_id: CLIENTS.fetch(:agent_a)
      )
      ids = payload.dig("data", "page", "items").map { _1.fetch("decision_id") }
      [ ids.include?(@luna_decision_id), payload ]
    end
  end

  def luna_testing_decision
    {
      statement_kind: "preference",
      topic_id: "testing.framework",
      effect: "prefer",
      modality: "should",
      value: {
        schema: "named-choice/v1",
        name: "rspec",
        items: nil,
        target_kind: nil,
        target_id: nil,
        action: nil
      },
      scope: {
        workspace_id: nil,
        repository_ids: [ @luna_repository_ids.fetch(:primary) ],
        branch_selectors: [],
        change_set_id: @luna_change_set_id,
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
        phases: [ "implementation" ],
        languages: [ "ruby" ],
        tags: [],
        repository_kinds: [],
        artifact_kinds: [],
        environments: []
      },
      validity: { valid_from: nil, valid_until: nil, until_event: nil },
      authority: { actor_id: "two-luna-user", role: "project-owner" },
      enforcement: { level: "advisory", retroactivity: "future_only", on_violation: "warn" },
      relations: { corrects: [], supersedes: [], exception_to: [], revokes: [] }
    }
  end

  def build_luna_merge_member(key:, candidates:, merge_commit_oid:, index:)
    repository_id = @luna_repository_ids.fetch(key)
    snapshot_id = "MERGE-TWO-LUNA-#{key.to_s.upcase}"
    registration = luna_successful_task(
      "merge_snapshot_register",
      {
        command_id: "two-luna.merge.register.#{index}",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        merge_snapshot_id: snapshot_id,
        repository_id:,
        target_branch: "main",
        target_base_commit_oid: BASE_COMMIT,
        ordered_candidates: candidates,
        merge_commit_oid:,
        producer: { name: "two-luna-merge-adapter", version: "1.0.0" },
        run_id: "two-luna-merge-#{index}",
        produced_at: "2026-08-28T10:0#{index}:00.000000Z"
      },
      client_id: CLIENTS.fetch(:verifier)
    ).fetch("data")
    luna_successful_task(
      "merge_verification_submit",
      {
        command_id: "two-luna.merge.verify.#{index}",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        merge_snapshot_id: snapshot_id,
        binding: {
          snapshot_event: registration.fetch("snapshot_event"),
          snapshot_digest: registration.fetch("snapshot_digest"),
          repository_id:,
          target_branch: "main",
          object_format: "sha1",
          target_base_commit_oid: BASE_COMMIT,
          ordered_candidates: candidates,
          merge_commit_oid:
        },
        assessment: {
          evidence_kind: "combined_tests",
          producer: { name: "two-luna-external-verifier", version: "1.0.0" },
          run_id: "two-luna-verification-#{index}",
          test_suite_digest: "sha256:#{index.to_s * 64}",
          environment_digest: "sha256:#{(index + 2).to_s * 64}",
          result_digest: "sha256:#{(index + 4).to_s * 64}",
          conclusion: "passed",
          findings: [],
          produced_at: "2026-08-28T10:1#{index}:00.000000Z"
        }
      },
      client_id: CLIENTS.fetch(:verifier)
    )
    snapshot = await_read_model("MergeSnapshot #{snapshot_id} verification") do
      payload = luna_query(
        "merge_snapshot_get",
        { merge_snapshot_id: snapshot_id },
        client_id: CLIENTS.fetch(:verifier)
      )
      [ payload.dig("data", "snapshot", "verification", "status") == "verified", payload ]
    end.dig("data", "snapshot")
    verified = snapshot.dig("verification", "verified")
    authorization = luna_successful_task(
      "merge_authorization_request",
      {
        command_id: "two-luna.merge.authorize.#{index}",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        merge_snapshot_id: snapshot_id,
        snapshot_binding: {
          registration_event: registration.fetch("snapshot_event"),
          snapshot_digest: registration.fetch("snapshot_digest"),
          verification_event: verified.dig("source", "event"),
          verification_digest: verified.fetch("verification_digest")
        },
        target_base_observation: {
          repository_id:,
          target_branch: "main",
          object_format: "sha1",
          commit_oid: BASE_COMMIT,
          observer: { name: "two-luna-git-fetch", version: "1.0.0" },
          run_id: "two-luna-base-#{index}",
          observed_at: "2026-08-28T10:2#{index}:00.000000Z"
        },
        expected_impact_policy: nil
      },
      client_id: CLIENTS.fetch(:verifier)
    ).fetch("data")
    assert_acceptance_equal("granted", authorization.fetch("outcome"), "Merge authorization")
    {
      snapshot_id:,
      repository_id:,
      merge_commit_oid:,
      authorization:,
      release_member: {
        repository_id:,
        target_branch: "main",
        object_format: "sha1",
        merge_snapshot_id: snapshot_id,
        snapshot_binding: {
          registration_event: registration.fetch("snapshot_event"),
          snapshot_digest: registration.fetch("snapshot_digest"),
          verification_event: verified.dig("source", "event"),
          verification_digest: verified.fetch("verification_digest")
        },
        authorization_event: authorization.fetch("decision_event"),
        authorization_decision_digest: authorization.fetch("decision_digest")
      }
    }
  end

  def record_luna_merge_observation_and_integration(member, index:)
    authorization = member.fetch(:authorization)
    observation = luna_successful_task(
      "merge_observation_record",
      {
        command_id: "two-luna.merge.observe.#{index}",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        merge_snapshot_id: member.fetch(:snapshot_id),
        authorization_event: authorization.fetch("decision_event"),
        authorization_decision_digest: authorization.fetch("decision_digest"),
        repository_id: member.fetch(:repository_id),
        target_branch: "main",
        object_format: "sha1",
        target_before_commit_oid: BASE_COMMIT,
        target_after_commit_oid: member.fetch(:merge_commit_oid),
        observer: { name: "two-luna-release-adapter", version: "1.0.0" },
        run_id: "two-luna-observation-#{index}",
        observed_at: "2026-08-28T10:4#{index}:00.000000Z"
      },
      client_id: CLIENTS.fetch(:verifier)
    ).fetch("data")
    luna_successful_task(
      "release_repository_integration_record",
      {
        command_id: "two-luna.release.integrate.#{index}",
        actor: { kind: "agent", id: CLIENTS.fetch(:verifier) },
        release_set_id: @luna_release_set_id,
        repository_id: member.fetch(:repository_id),
        attempt_id: "two-luna-release-attempt-#{index}",
        outcome: "integrated",
        merge_observation_event: observation.fetch("observation_event"),
        observation_digest: observation.fetch("observation_digest"),
        failure: nil
      },
      client_id: CLIENTS.fetch(:verifier)
    ).fetch("data")
  end

  def capture_luna_release_index
    content = JSON.generate(
      change_set_id: @luna_change_set_id,
      release_set_id: @luna_release_set_id,
      skill: { name: "checkpointed-coordination", scope: @luna_scope },
      decision_id: @luna_decision_id
    )
    receipt = luna_successful_task(
      "development_artifact_capture",
      {
        command_id: "two-luna.artifact.release-index",
        actor: { kind: "agent", id: CLIENTS.fetch(:agent_a) },
        scope: @luna_scope,
        title: "Two-Luna release reconstruction index",
        kind: "repository_checkpoint",
        labels: [ "release-index", "two-luna" ],
        content: { encoding: "utf-8", media_type: "application/json", text: content },
        source: {
          kind: "generated",
          locator: "mcp://two-luna/release-index",
          revision: nil,
          observed_at: "2026-08-28T11:00:00.000000Z",
          collector: "two-luna-acceptance/v1"
        }
      },
      client_id: CLIENTS.fetch(:agent_a)
    ).fetch("data")
    @luna_artifact_id = receipt.fetch("artifact_id")
    await_read_model("release-index Artifact to become discoverable") do
      payload = luna_query(
        "development_artifact_list",
        { scope: @luna_scope, labels: [ "release-index" ], limit: 20 },
        client_id: CLIENTS.fetch(:replacement)
      )
      ids = payload.dig("data", "page", "items").map { _1.fetch("artifact_id") }
      [ ids.include?(@luna_artifact_id), payload ]
    end
  end

  def luna_task_handle(tool, arguments, client_id:)
    response = luna_round_trip(call_tool(tool, luna_round_trip(arguments), client_id:))
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "#{tool} did not return a Task handle: #{response.inspect}")
    { tool:, task_id:, client_id: }.freeze
  end

  def luna_task_result(handle)
    state = luna_round_trip(
      await_task_terminal(handle.fetch(:task_id), client_id: handle.fetch(:client_id))
    )
    assert_acceptance_equal(
      "completed",
      state.dig("result", "status"),
      "#{handle.fetch(:tool)} Task: #{state.inspect}"
    )
    state.dig("result", "result", "structuredContent")
  end

  def luna_task(tool, arguments, client_id:)
    collector = ReportedErrorCollector.new(errors: [])
    Rails.error.subscribe(collector)
    luna_task_result(luna_task_handle(tool, arguments, client_id:))
  rescue StandardError
    raise collector.errors.first if collector.errors.any?

    raise
  ensure
    Rails.error.unsubscribe(collector) if collector
  end

  def luna_successful_task(tool, arguments, client_id:)
    content = luna_task(tool, arguments, client_id:)
    assert_acceptance_equal("ok", content.fetch("status"), "#{tool} result")
    content
  end

  def luna_query(tool, arguments, client_id:)
    luna_round_trip(
      call_tool(tool, luna_round_trip(arguments), client_id:)
        .dig("result", "structuredContent")
    )
  end

  def luna_round_trip(value)
    JSON.parse(JSON.generate(value))
  end
end

World(LiveTwoAgentAcceptanceWorld)

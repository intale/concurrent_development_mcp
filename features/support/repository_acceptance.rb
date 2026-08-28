# frozen_string_literal: true

module RepositoryAcceptance
  DEFAULT_REPOSITORY_ID = "01a03deb-6f55-74ba-bcc0-afd02e7b14dc"
  DEFAULT_SCOPE = "project:test/billing"

  def acceptance_repository_id(key = "billing")
    value = key.to_s
    return value if Coordinator::Shared::Types::UUID_V7_PATTERN.match?(value)
    return DEFAULT_REPOSITORY_ID if value == "billing"

    digest = Coordinator::Shared::CanonicalJson.new.sha256(
      { "test_repository" => value }
    ).delete_prefix("sha256:")
    "01a03deb-#{digest[0, 4]}-7#{digest[4, 3]}-8#{digest[7, 3]}-#{digest[10, 12]}"
  end

  def acceptance_repository_scope(key = "billing")
    value = key.to_s
    return DEFAULT_SCOPE if value == "billing" || value == DEFAULT_REPOSITORY_ID

    "project:test/#{value}"
  end

  def register_acceptance_repository(key = "billing")
    repository_id = acceptance_repository_id(key)
    return repository_id if registered_acceptance_repositories.include?(repository_id)

    response = call_tool(
      "repository_register",
      {
        command_id: "seed-register-#{repository_id}",
        actor: { kind: "agent", id: "test-repository-registrar" },
        repository_id:,
        scope: acceptance_repository_scope(key),
        repository_key: key.to_s,
        display_name: "#{key.to_s.capitalize} test repository",
        paths: [],
        remotes: []
      },
      client_id: "test-repository-bootstrap"
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "repository_register did not return a Task: #{response.inspect}")
    start_process_subscriptions
    state = await_task_terminal(task_id, client_id: "test-repository-bootstrap")
    assert_acceptance_equal(false, state.dig("result", "result", "isError"), "Repository bootstrap")
    await_read_model("Repository #{repository_id} to reach scoped discovery") do
      payload = call_tool(
        "repository_list",
        { scope: acceptance_repository_scope(key), repository_key: key.to_s, limit: 20 },
        client_id: "test-repository-bootstrap"
      ).dig("result", "structuredContent")
      items = payload.dig("data", "page", "items") || []
      [ items.any? { _1.fetch("repository_id") == repository_id }, payload ]
    end
    stop_live_subscriptions
    registered_acceptance_repositories << repository_id
    repository_id
  end

  def reset_acceptance_repositories!
    @registered_acceptance_repositories = []
  end

  def repository_distinct_lane_command_ids(prefix)
    lane = Coordinator::Write::Tasks::ExecutionLane.new
    by_lane = {}
    64.times do |index|
      command_id = "#{prefix}.#{index}"
      by_lane[lane.index(command_id)] ||= command_id
      break if by_lane.length == Coordinator::Write::Tasks::ExecutionLane::COUNT
    end
    assert_acceptance_equal(
      Coordinator::Write::Tasks::ExecutionLane::COUNT,
      by_lane.length,
      "Distinct repository-registration execution lanes"
    )
    by_lane.sort.map(&:last)
  end

  def prepare_shared_repository_lease_attempts(repository_id)
    change_set_id = "CS-AUD2-REPOSITORY-NAMESPACE"
    participants = [
      { agent_id: "agent-a", work_item_id: "W-AUD2-REPOSITORY-A", attempt_id: "A-AUD2-REPOSITORY-A" },
      { agent_id: "agent-b", work_item_id: "W-AUD2-REPOSITORY-B", attempt_id: "A-AUD2-REPOSITORY-B" }
    ]
    submit_and_execute(
      "change_set_create",
      command_id: "audit2.repository-namespace.create",
      actor: { kind: "agent", id: "repository-planner" },
      change_set_id:,
      goal: "Prove clean clients share one repository lease namespace",
      acceptance_criteria: [ "One overlapping file lease is authoritative" ]
    )
    participants.each do |participant|
      submit_and_execute(
        "work_item_create",
        command_id: "audit2.repository-namespace.#{participant.fetch(:agent_id)}.create",
        actor: { kind: "agent", id: "repository-planner" },
        change_set_id:,
        work_item_id: participant.fetch(:work_item_id),
        repository_id:,
        goal: "Coordinate #{participant.fetch(:agent_id)}",
        acceptance_criteria: [ "The shared file cannot be leased twice" ]
      )
    end
    submit_and_execute(
      "change_set_activate",
      command_id: "audit2.repository-namespace.activate",
      actor: { kind: "agent", id: "repository-planner" },
      change_set_id:
    )
    participants.each { await_work_item_ready(_1.fetch(:work_item_id)) }
    participants.each do |participant|
      submit_and_execute(
        "work_item_acquire",
        client_id: participant.fetch(:agent_id),
        command_id: "audit2.repository-namespace.#{participant.fetch(:agent_id)}.acquire",
        actor: { kind: "agent", id: participant.fetch(:agent_id) },
        change_set_id:,
        work_item_id: participant.fetch(:work_item_id),
        attempt_id: participant.fetch(:attempt_id),
        base_snapshots: [ { repository_id:, commit_oid: "a" * 40 } ]
      )
    end

    [ change_set_id, participants ]
  end

  def contend_for_shared_repository_file(repository_id)
    change_set_id, participants = prepare_shared_repository_lease_attempts(repository_id)
    participants.map do |participant|
      task_id = submit_and_execute(
        "write_set_reserve",
        client_id: participant.fetch(:agent_id),
        command_id: "audit2.repository-namespace.#{participant.fetch(:agent_id)}.reserve",
        actor: { kind: "agent", id: participant.fetch(:agent_id) },
        change_set_id:,
        work_item_id: participant.fetch(:work_item_id),
        attempt_id: participant.fetch(:attempt_id),
        repository_id:,
        base_commit_oid: "a" * 40,
        resources: [
          {
            kind: "file",
            path: "app/models/shared_repository.rb",
            base_blob_oid: "b" * 40
          }
        ],
        lease_duration_seconds: 300
      )
      task_request("tasks/get", task_id, client_id: participant.fetch(:agent_id))
        .dig("result", "result", "structuredContent")
    end
  end

  private

  def registered_acceptance_repositories
    @registered_acceptance_repositories ||= []
  end
end

World(RepositoryAcceptance)

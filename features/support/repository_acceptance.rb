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
        { scope: acceptance_repository_scope(key), limit: 20 },
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

  private

  def registered_acceptance_repositories
    @registered_acceptance_repositories ||= []
  end
end

World(RepositoryAcceptance)

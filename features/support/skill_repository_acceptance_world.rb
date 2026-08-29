# frozen_string_literal: true

module SkillRepositoryAcceptanceWorld
  def publish_skill_task(
    name:,
    scope:,
    command_id:,
    expected_revision:,
    instructions:,
    assets: []
  )
    publication = submit_skill_task(
      "skill_publish",
      name:,
      scope:,
      command_id:,
      expected_revision:,
      instructions:,
      assets:
    )
    start_process_subscriptions
    state = await_task_terminal(publication.fetch(:task_id), client_id: publication.fetch(:client_id))
    publication.merge(
      state:,
      outcome: state.dig("result", "result", "structuredContent")
    )
  end

  def submit_skill_task(
    _tool = "skill_publish",
    name:,
    scope:,
    command_id:,
    expected_revision:,
    instructions:,
    assets: [],
    client_id: "skill-agent"
  )
    response = call_tool(
      "skill_publish",
      {
      command_id:,
      actor: { kind: "agent", id: client_id },
      name:,
      scope:,
      expected_revision:,
      description: "#{name} for #{scope}",
      instructions:,
      assets:
      },
      client_id:
    )
    task_id = response.dig("result", "taskId")
    assert_acceptance(task_id, "skill_publish did not return a Task: #{response.inspect}")
    {
      task_id:,
      command_id:,
      client_id:,
      arguments: {
        name:,
        scope:,
        expected_revision:,
        instructions:,
        assets:
      }
    }
  end

  def skill_events(name:, scope:)
    identity = Coordinator::Write::Skills::IdentityBuilder.new.call(name:, scope:)
    event_store.read(
      streams.skill(identity.skill_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRevisionPublished" ],
        maximum_count: 100,
        direction: :asc
      )
    )
  end

  def project_skill_event(event)
    await_read_model(
      "Skill #{event.data.fetch('name')} revision #{event.data.fetch('revision')} to become available"
    ) do
      payload = skill_view(
        name: event.data.fetch("name"),
        scope: event.data.fetch("scope"),
        revision: event.data.fetch("revision")
      )
      [ payload.dig("data", "skill", "revision") == event.data.fetch("revision"), payload ]
    end
  end

  def skill_view(name:, scope:, revision: nil)
    call_tool("skill_get", { name:, scope:, revision: }.compact).dig("result", "structuredContent")
  end

  def skill_asset(name:, scope:, path:, revision: nil)
    call_tool("skill_asset_get", { name:, scope:, path:, revision: }.compact).dig("result", "structuredContent")
  end

  def script_asset(path, content)
    {
      path:,
      executable: true,
      content: {
        encoding: "utf-8",
        media_type: "text/x-shellscript",
        text: content
      }
    }
  end
end

World(SkillRepositoryAcceptanceWorld)

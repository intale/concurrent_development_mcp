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
    task_id = submit_and_execute(
      "skill_publish",
      command_id:,
      actor: { kind: "agent", id: "skill-agent" },
      name:,
      scope:,
      expected_revision:,
      description: "#{name} for #{scope}",
      instructions:,
      assets:
    )
    state = task_request("tasks/get", task_id)
    {
      task_id:,
      command_id:,
      state:,
      outcome: state.dig("result", "result", "structuredContent")
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
    Coordinator::Container["projectors.skills_v1"].call(event)
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
      media_type: "text/x-shellscript",
      executable: true,
      content_base64: [ content ].pack("m0")
    }
  end
end

World(SkillRepositoryAcceptanceWorld)

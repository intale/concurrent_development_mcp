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
    marker = Coordinator::Write::Skills::MarkerBuilder.new.natural_key(name:, scope:)
    registration = read_global_marked_events(
      stream_context: "AgentKnowledge",
      stream_name: "Skill",
      event_types: [ "SkillRegistered" ],
      marker:,
      maximum_count: 1
    ).first
    return [] unless registration

    event_store.read(
      streams.skill(registration.data.fetch("skill_id")),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRevisionPublished" ],
        maximum_count: 100,
        direction: :asc
      )
      )
  end

  def skill_registration(skill_id)
    event_store.read(
      streams.skill(skill_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRegistered" ],
        maximum_count: 1,
        direction: :asc
      )
    ).first
  end

  def skill_fact_events(name:, scope:)
    registration = read_global_marked_events(
      stream_context: "AgentKnowledge",
      stream_name: "Skill",
      event_types: [ "SkillRegistered" ],
      marker: Coordinator::Write::Skills::MarkerBuilder.new.natural_key(name:, scope:),
      maximum_count: 1
    ).first
    return [] unless registration

    publications = skill_events(name:, scope:)
    facts = [ registration ] + publications
    publications.each do |publication|
      revision_id = publication.data.fetch("skill_revision_id")
      revision_events = event_store.read(
        streams.skill_revision(revision_id),
        Coordinator::Write::EventReadCriteria.new(
          event_types: %w[
            SkillRevisionCreated
            SkillRevisionDescriptionDefined
            SkillRevisionInstructionsDefined
            SkillAssetAddedToRevision
          ],
          maximum_count: 100,
          direction: :asc
        )
      )
      facts.concat(revision_events)
      revision_events.select { _1.type == "SkillAssetAddedToRevision" }.each do |assignment|
        facts.concat(
          event_store.read(
            streams.skill_asset(assignment.data.fetch("asset_id")),
            Coordinator::Write::EventReadCriteria.new(
              event_types: %w[
                SkillAssetCreated
                SkillAssetPathDefined
                SkillAssetContentDefined
                SkillAssetExecutabilityDefined
              ],
              maximum_count: 10,
              direction: :asc
            )
          )
        )
      end
    end
    facts.uniq(&:id).sort_by(&:global_position)
  end

  def await_skill_revision(event)
    registration = skill_registration(event.data.fetch("skill_id"))
    assert_acceptance(registration, "Skill #{event.data.fetch('skill_id')} has no registration fact")
    await_read_model(
      "Skill #{registration.data.fetch('name')} revision #{event.data.fetch('revision')} to become available"
    ) do
      payload = skill_view(
        name: registration.data.fetch("name"),
        scope: registration.data.fetch("scope")
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

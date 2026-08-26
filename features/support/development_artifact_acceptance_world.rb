# frozen_string_literal: true

module DevelopmentArtifactAcceptanceWorld
  def capture_artifact_task(
    command_id:,
    title:,
    kind:,
    labels:,
    locator:,
    source_kind:,
    content:,
    scope: "project:acceptance",
    revision: nil
  )
    task_id = submit_and_execute(
      "development_artifact_capture",
      command_id:,
      actor: { kind: "agent", id: "artifact-agent" },
      scope:,
      title:,
      kind:,
      labels:,
      content:,
      source: {
        kind: source_kind,
        locator:,
        revision:,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "cucumber/v1"
      }
    )
    state = task_request("tasks/get", task_id)
    state.dig("result", "result", "structuredContent")
  end

  def declare_artifact_relation_task(
    command_id:,
    source_artifact_id:,
    relation:,
    target:,
    attributes: {},
    supersedes: nil
  )
    arguments = {
      command_id:,
      actor: { kind: "agent", id: "artifact-agent" },
      source_artifact_id:,
      relation:,
      target:,
      attributes:
    }
    arguments[:supersedes] = supersedes if supersedes
    task_id = submit_and_execute("development_artifact_relation_declare", **arguments)
    {
      task_id:,
      result: task_request("tasks/get", task_id)
        .dig("result", "result", "structuredContent")
    }
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end

  def project_artifact(artifact_id)
    artifact_events(artifact_id).each do |event|
      Coordinator::Container["projectors.development_artifacts_v1"].call(event)
    end
  end

  def project_artifact_event(event)
    Coordinator::Container["projectors.development_artifacts_v1"].call(event)
  end

  def artifact_view(artifact_id)
    call_tool("development_artifact_get", { artifact_id: })
      .dig("result", "structuredContent")
  end

  def artifact_content(artifact_id)
    call_tool("development_artifact_content_get", { artifact_id: })
      .dig("result", "structuredContent")
  end


  def artifact_relation_page(
    artifact_id,
    direction:,
    limit: 20,
    cursor: nil,
    include_superseded: false
  )
    arguments = { artifact_id:, direction:, limit:, include_superseded: }
    arguments[:cursor] = cursor if cursor
    call_tool("development_artifact_relation_list", arguments)
      .dig("result", "structuredContent", "data", "page")
  end

  def artifact_locator_page(locator, source_revision: :unspecified, cursor: nil, limit: 20)
    arguments = {
      scope: "project:acceptance",
      source_kind: "local_file",
      locator:,
      limit:
    }
    arguments[:source_revision] = source_revision unless source_revision == :unspecified
    arguments[:cursor] = cursor if cursor
    call_tool("development_artifact_locator_resolve", arguments)
      .dig("result", "structuredContent")
  end

  def follow_artifact_action(action)
    call_tool(action.fetch("tool"), action.fetch("arguments"))
      .dig("result", "structuredContent")
  end
end

World(DevelopmentArtifactAcceptanceWorld)

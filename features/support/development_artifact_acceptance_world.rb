# frozen_string_literal: true

module DevelopmentArtifactAcceptanceWorld
  def capture_artifact_task(
    command_id:,
    title:,
    kind:,
    labels:,
    locator:,
    source_kind:,
    content:
  )
    task_id = submit_and_execute(
      "development_artifact_capture",
      command_id:,
      actor: { kind: "agent", id: "artifact-agent" },
      scope: "project:acceptance",
      title:,
      kind:,
      labels:,
      content:,
      source: {
        kind: source_kind,
        locator:,
        revision: nil,
        observed_at: "2026-08-25T16:00:00.000000Z",
        collector: "cucumber/v1"
      }
    )
    state = task_request("tasks/get", task_id)
    state.dig("result", "result", "structuredContent")
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

  def artifact_view(artifact_id)
    call_tool("development_artifact_get", { artifact_id: })
      .dig("result", "structuredContent")
  end

  def artifact_content(artifact_id)
    call_tool("development_artifact_content_get", { artifact_id: })
      .dig("result", "structuredContent")
  end
end

World(DevelopmentArtifactAcceptanceWorld)

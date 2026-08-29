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
    revision: nil,
    actor_id: "artifact-agent",
    client_id: "default"
  )
    task_id = submit_and_execute(
      "development_artifact_capture",
      client_id:,
      command_id:,
      actor: { kind: "agent", id: actor_id },
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
    state = task_request("tasks/get", task_id, client_id:)
    state.dig("result", "result", "structuredContent")
  end

  def declare_artifact_relation_task(
    command_id:,
    source_artifact_id:,
    relation:,
    target:,
    attributes: {},
    supersedes: nil,
    actor_id: "artifact-agent",
    client_id: "default"
  )
    arguments = {
      command_id:,
      actor: { kind: "agent", id: actor_id },
      source_artifact_id:,
      relation:,
      target:,
      attributes:
    }
    arguments[:supersedes] = supersedes if supersedes
    task_id = submit_and_execute(
      "development_artifact_relation_declare",
      client_id:,
      **arguments
    )
    {
      task_id:,
      result: task_request("tasks/get", task_id, client_id:)
        .dig("result", "result", "structuredContent")
    }
  end

  def artifact_events(artifact_id)
    event_store.read(
      streams.development_artifact(artifact_id),
      Coordinator::Write::EventQueries::DEVELOPMENT_ARTIFACT_HISTORY
    )
  end

  def project_artifact(artifact_id, observation_id: nil)
    await_read_model("Development Artifact #{artifact_id} to become available") do
      payload = artifact_view(artifact_id, observation_id:)
      artifact = payload.dig("data", "artifact", "artifact")
      matches = artifact&.fetch("artifact_id") == artifact_id &&
                (!observation_id || artifact.fetch("observation_id") == observation_id)
      [ matches, payload ]
    end
  end

  def project_artifact_event(event)
    case event.type
    when "DevelopmentArtifactCaptured"
      artifact_id = event.data.fetch("artifact").fetch("artifact_id")
      project_artifact(artifact_id)
    when "DevelopmentArtifactRelationDeclared"
      artifact_id = event.data.fetch("artifact_relation").fetch("source_artifact_id")
      relation_id = event.data.dig("artifact_relation", "relation_id")
      await_artifact_relation(artifact_id, relation_id:, status: "active")
    when "DevelopmentArtifactRelationSuperseded"
      artifact_id = event.data.fetch("source_artifact_id")
      relation_id = event.data.fetch("superseded_relation_id")
      await_artifact_relation(artifact_id, relation_id:, status: "superseded")
    end
  end

  def artifact_view(artifact_id, observation_id: nil)
    arguments = { artifact_id: }
    arguments[:observation_id] = observation_id if observation_id
    call_tool("development_artifact_get", arguments)
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

  def await_artifact_relation(artifact_id, relation_id:, status:)
    await_read_model("Artifact relation #{relation_id} to become #{status}") do
      page = artifact_relation_page(
        artifact_id,
        direction: "outgoing",
        limit: 100,
        include_superseded: true
      )
      item = page&.fetch("items", [])&.find { _1.fetch("relation_id") == relation_id }
      [ item&.fetch("status") == status, page ]
    end
  end


  def submit_artifact_relation_batch(items, command_suffix:)
    batch_id = SecureRandom.uuid_v7
    task_id = submit_and_execute(
      "development_artifact_relation_declare_batch",
      command_id: "cmd-cuc-artifact-relation-batch-#{command_suffix}",
      actor: { kind: "agent", id: "artifact-batch-agent" },
      batch_id:,
      items:
    )
    state = task_request("tasks/get", task_id)
    assert_acceptance_equal("completed", state.dig("result", "status"), "Relation Batch Task")
    await_artifact_relation_batch(batch_id)
  end

  def await_artifact_relation_batch(batch_id)
    start_process_subscriptions
    eventually("Artifact relation Batch #{batch_id} to become terminal", timeout_seconds: 30) do
      events = artifact_relation_batch_events(batch_id)
      terminal = events.any? do |event|
        %w[OperationBatchCompleted OperationBatchCancelled].include?(event.type)
      end
      [ terminal, events.map(&:type) ]
    end
    await_read_model(
      "Artifact relation Batch #{batch_id} to become queryable",
      timeout_seconds: 60
    ) do
      payload = call_tool(
        "operation_batch_get",
        { batch_id:, limit: Coordinator::Shared::Types::OPERATION_BATCH_QUERY_MAXIMUM_ITEMS }
      ).dig("result", "structuredContent")
      status = payload.dig("data", "batch", "status")
      [ %w[completed completed_with_errors cancelled].include?(status), payload ]
    end
  end

  def artifact_relation_batch_events(batch_id)
    event_store.read(
      streams.operation_batch(batch_id),
      Coordinator::Write::EventQueries::OPERATION_BATCH_HISTORY
    )
  end

  def await_artifact_relation_count(artifact_id, count, include_superseded: true)
    await_read_model("Artifact #{artifact_id} to expose #{count} relationships") do
      page = artifact_relation_page(
        artifact_id,
        direction: "outgoing",
        limit: Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_QUERY_MAXIMUM_ITEMS,
        include_superseded:
      )
      [ page&.fetch("items", [])&.length == count, page ]
    end
  end
end

World(DevelopmentArtifactAcceptanceWorld)

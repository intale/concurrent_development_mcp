# frozen_string_literal: true

require Rails.root.join("spec/support/repository_scenario").to_s
require Rails.root.join("spec/support/resource_scenario").to_s
require Rails.root.join("spec/support/candidate_scenario").to_s
require Rails.root.join("spec/support/merge_snapshot_scenario").to_s
require Rails.root.join("spec/support/release_set_scenario").to_s

module ReleaseSetAcceptanceWorld
  def release_set_events(release_set_id)
    event_store.read(
      streams.release_set(release_set_id),
      Coordinator::Write::EventQueries::RELEASE_SET_PREPARATION
    )
  end

  def release_set_lifecycle_events(release_set_id)
    event_store.read(
      streams.release_set(release_set_id),
      Coordinator::Write::EventQueries::RELEASE_SET_LIFECYCLE
    )
  end

  def release_set_payload(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def release_event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def release_set_view(release_set_id)
    call_tool("release_set_get", { release_set_id: })
      .dig("result", "structuredContent")
  end

  def expected_release_repository_ids
    ReleaseSetScenario::REPOSITORIES.map { acceptance_repository_id(_1) }
  end
end

World(ReleaseSetAcceptanceWorld)

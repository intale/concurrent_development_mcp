# frozen_string_literal: true

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

  def release_set_view(release_set_id)
    call_tool("release_set_get", { release_set_id: })
      .dig("result", "structuredContent")
  end
end

World(ReleaseSetAcceptanceWorld)

# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCaptureBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture_batch"
    title "Capture a batch of Development Artifacts"
    description <<~TEXT.squish
      Import pass 1: inventory content using capabilities available to the client, then capture
      all selected exact bytes as 1..1,000 ordinary commands within the 3-MiB canonical-input
      limit. Poll tasks/get until the whole bounded Saga settles; its final result reports
      successful, rejected, failed and unexecuted items without rolling back earlier successes.
      operation_batch_get is optional projected per-item context, not persistence confirmation.
      Initial acceptance stores only the manifest; each child request is bound
      independently as the Saga reaches it. Identical requests reuse their canonical result.
      Then
      build an exact scope/source-kind/locator/revision to Artifact-ID map. The server assumes
      no project path layout, runtime, filesystem, Git, URL fetching, or shared container. If
      the Task result is unknown, replay the exact payload and command_id; a new intent after
      a known terminal result uses a new command_id.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture_batch
    operation "operations.submit_create_development_artifact_capture_batch_task"
  end
end

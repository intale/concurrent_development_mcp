# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCaptureBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture_batch"
    title "Capture a batch of Development Artifacts"
    description <<~TEXT.squish
      Import pass 1: inventory content using capabilities available to the client, then capture
      all selected exact bytes as 1..1,000 ordinary commands within the 3-MiB canonical-input
      limit. Poll the returned Task, then operation_batch_get for per-item Saga outcomes and
      build an exact scope/source-kind/locator/revision to Artifact-ID map. The server assumes
      no project path layout, runtime, filesystem, Git, URL fetching, or shared container. If
      the Task result is unknown, replay the exact payload and command_id; a new intent after
      a known terminal result uses a new command_id.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture_batch
    output_schema Coordinator::Mcp::ArtifactSchemas.operation_batch_acceptance_result
    operation "operations.submit_create_development_artifact_capture_batch_task"
  end
end

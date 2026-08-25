# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCaptureBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture_batch"
    title "Capture a batch of Development Artifacts"
    description "Bulk-import caller-selected passive development memory as 1..1,000 ordinary capture commands within the 3-MiB canonical-input limit. The asynchronous Saga records an independent outcome for every item; the server assumes no project path layout."
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture_batch
    operation "operations.submit_create_development_artifact_capture_batch_task"
  end
end

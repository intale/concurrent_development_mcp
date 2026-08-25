# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCaptureBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture_batch"
    title "Capture a batch of Development Artifacts"
    description "Start an idempotent Saga that captures up to 1,000 immutable Development Artifacts."
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture_batch
    operation "operations.submit_create_development_artifact_capture_batch_task"
  end
end

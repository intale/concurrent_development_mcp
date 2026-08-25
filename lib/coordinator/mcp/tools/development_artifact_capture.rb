# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCapture < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture"
    title "Capture a Development Artifact"
    description "Capture immutable development evidence with exact classification and attributed provenance. Content remains passive."
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture
    operation "operations.submit_capture_development_artifact_task"
  end
end

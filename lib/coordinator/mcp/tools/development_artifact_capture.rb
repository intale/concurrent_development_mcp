# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCapture < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture"
    title "Capture a Development Artifact"
    description "Capture one immutable passive development-memory item chosen by the caller from a project it can inspect. Send exact bytes and caller-observed provenance; the server never dereferences source.locator."
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture
    operation "operations.submit_capture_development_artifact_task"
  end
end

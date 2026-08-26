# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactCapture < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_capture"
    title "Capture a Development Artifact"
    description <<~TEXT.squish
      Import pass 1 for one item from a project it can inspect: capture exact bytes and
      caller-observed provenance before declaring links. The server never reads source.locator.
      This call returns a Task; poll tasks/get. If its result is unknown, replay the exact
      payload with the same command_id; after a known terminal result, a changed retry intent
      needs a new command_id.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_capture
    output_schema Coordinator::Mcp::ArtifactSchemas.capture_result
    operation "operations.submit_capture_development_artifact_task"
  end
end

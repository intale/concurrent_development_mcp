# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactUpdate < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_update"
    title "Update a Development Artifact"
    description <<~TEXT.squish
      Update one or more mutable properties of a Development Artifact. The server reads
      the authoritative Artifact stream, emits only changed granular property facts, and
      rejects a stale expected_revision. This call returns a Task; poll tasks/get.
      Content bytes are never read from a locator and are represented as UTF-8 text or
      canonical Base64 for binary data.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_update
    output_schema Coordinator::Mcp::ArtifactSchemas.update_result
    operation "operations.submit_update_development_artifact_task"
  end
end

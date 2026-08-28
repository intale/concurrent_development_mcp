# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactClassificationCorrect < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_classification_correct"
    title "Correct a Development Artifact observation classification"
    description <<~TEXT.squish
      Correct only the caller-assigned title, kind, and labels of one immutable Artifact
      observation. Pass the exact observation_id and classification_revision returned by
      development_artifact_get; a stale expected revision is rejected without changing facts.
      Content bytes, media type, source locator, source revision, and provenance remain immutable.
      This call returns a Task; poll tasks/get.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_classification_correct
    output_schema Coordinator::Mcp::ArtifactSchemas.classification_result
    operation "operations.submit_correct_development_artifact_classification_task"
  end
end

# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationDeclare < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_relation_declare"
    title "Relate a Development Artifact"
    description <<~TEXT.squish
      Import pass 2 for one caller-discovered directed edge. For references or contains, source
      is the parent/index Artifact and target is the linked child. Preserve literal path and
      fragment plus the caller-computed normalized_locator; the server does not parse, resolve,
      or dereference them. Poll the returned Task. Replay the same command_id and payload only
      when its result is unknown; use a new command_id for a new intent after a known result.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_declare
    output_schema Coordinator::Mcp::ArtifactSchemas.relation_declare_result
    operation "operations.submit_declare_development_artifact_relation_task"
  end
end

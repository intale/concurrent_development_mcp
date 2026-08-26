# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationDeclareBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_relation_declare_batch"
    title "Relate a batch of Development Artifacts"
    description <<~TEXT.squish
      Import pass 2: after every selected item is captured and mapped, parse links client-side,
      split fragments, normalize relative POSIX locators against the source locator, resolve
      exact targets, and declare 1..1,000 idempotent edges within the 3-MiB limit. Preserve
      literal link evidence; never guess unresolved or ambiguous targets—record those outcomes
      in a caller-captured import_manifest Artifact instead. Poll the returned Task, then
      operation_batch_get for every per-item Saga outcome. Unknown result means replay the
      exact command_id and payload; a known terminal result followed by new intent needs a new
      command_id.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_declare_batch
    output_schema Coordinator::Mcp::ArtifactSchemas.operation_batch_acceptance_result
    operation "operations.submit_create_development_artifact_relation_declare_batch_task"
  end
end

# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationDeclareBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_relation_declare_batch"
    title "Relate a batch of Development Artifacts"
    description "Start an idempotent Saga that declares up to 1,000 typed Artifact relationships."
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_declare_batch
    operation "operations.submit_create_development_artifact_relation_declare_batch_task"
  end
end

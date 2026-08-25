# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationDeclareBatch < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_relation_declare_batch"
    title "Relate a batch of Development Artifacts"
    description "Bulk-import 1..1,000 caller-discovered typed Artifact relationships within the 3-MiB canonical-input limit. The asynchronous Saga records an independent outcome for every item."
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_declare_batch
    operation "operations.submit_create_development_artifact_relation_declare_batch_task"
  end
end

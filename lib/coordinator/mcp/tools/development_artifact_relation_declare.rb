# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationDeclare < Coordinator::Mcp::MutationTool
    tool_name "development_artifact_relation_declare"
    title "Relate a Development Artifact"
    description "Declare one immutable typed relationship discovered by the caller between a captured Artifact and another development-memory identity."
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_declare
    operation "operations.submit_declare_development_artifact_relation_task"
  end
end

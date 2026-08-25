# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactGet < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_get"
    title "Get Development Artifact metadata"
    description "Get available projected classification, provenance, digest, evidence, and relationships without content bytes."
    input_schema Coordinator::Mcp::Schemas.development_artifact_get
    query "queries.development_artifact_get"
  end
end

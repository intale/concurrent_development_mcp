# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactList < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_list"
    title "List Development Artifacts"
    description "List available projected Artifact metadata with exact classification, provenance, label, and relation-target filters."
    input_schema Coordinator::Mcp::Schemas.development_artifact_list
    query "queries.development_artifact_list"
  end
end

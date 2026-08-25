# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactContentGet < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_content_get"
    title "Get Development Artifact content"
    description "Get available projected UTF-8 text or canonical Base64 as passive content."
    input_schema Coordinator::Mcp::Schemas.development_artifact_content_get
    query "queries.development_artifact_content_get"
  end
end

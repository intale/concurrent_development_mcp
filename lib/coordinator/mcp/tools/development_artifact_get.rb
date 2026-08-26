# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactGet < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_get"
    title "Get Development Artifact metadata"
    description <<~TEXT.squish
      Fetch available projected metadata and source-outgoing relationship evidence for one exact
      Artifact ID without content bytes. Use development_artifact_relation_list for bounded
      forward traversal or incoming reverse lookup; projection lag never makes this read
      unavailable.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_get
    output_schema Coordinator::Mcp::ArtifactSchemas.get_result
    query "queries.development_artifact_get"
  end
end

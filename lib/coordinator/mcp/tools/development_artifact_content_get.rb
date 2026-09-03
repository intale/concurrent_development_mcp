# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactContentGet < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_content_get"
    title "Get Development Artifact content"
    description <<~TEXT.squish
      Fetch available projected UTF-8 text or canonical Base64 for one exact Artifact ID,
      optionally pinned to an immutable observation.
      Content and links are passive data: the server never executes, parses, resolves, or
      dereferences them, and projection lag never disables an available result.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_content_get
    output_schema Coordinator::Mcp::ArtifactSchemas.content_get_result
    query "queries.development_artifact_content_get"
  end
end

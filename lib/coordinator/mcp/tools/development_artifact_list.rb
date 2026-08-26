# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactList < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_list"
    title "List Development Artifacts"
    description <<~TEXT.squish
      Inventory available projected Artifact metadata in capture order with exact classification,
      provenance, label, and relation-target filters. This is not link resolution: use exact
      locator resolution for parsed locators and relation traversal for parent/child navigation.
      Available stale results are served without a freshness gate.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_list
    output_schema Coordinator::Mcp::ArtifactSchemas.list_result
    query "queries.development_artifact_list"
  end
end

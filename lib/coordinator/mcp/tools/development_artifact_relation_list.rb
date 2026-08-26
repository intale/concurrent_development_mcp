# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationList < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_relation_list"
    title "List directed Development Artifact relationships"
    description <<~TEXT.squish
      Traverse the directed graph from one exact Artifact ID. Use outgoing from a parent/index
      to its linked children, incoming from a child to every exact parent, or both; optional
      relation filtering and peer summaries avoid broad scans and N+1 inference. Follow the
      projection-observation continuation cursor until has_more is false, and reuse the returned
      cursor later to discover older event positions projected after the previous window.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_list
    output_schema Coordinator::Mcp::ArtifactSchemas.relation_list_result
    query "queries.development_artifact_relation_list"
  end
end

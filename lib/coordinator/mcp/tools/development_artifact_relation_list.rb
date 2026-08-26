# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactRelationList < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_relation_list"
    title "List directed Development Artifact relationships"
    description <<~TEXT.squish
      Traverse available projected Artifact relationships in incoming, outgoing, or both
      directions with an optional relation-kind filter and bounded continuation cursor.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_relation_list
    query "queries.development_artifact_relation_list"
  end
end

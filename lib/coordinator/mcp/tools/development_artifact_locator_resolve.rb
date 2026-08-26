# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactLocatorResolve < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_locator_resolve"
    title "Resolve an exact Development Artifact locator"
    description <<~TEXT.squish
      Resolve an exact caller-owned logical locator within one scope and source kind. For a
      relative document link, the client splits its fragment and normalizes the path against
      the source locator using POSIX semantics before lookup; URLs remain exact. Omit
      source_revision to receive explicit absent, unique, or ambiguous immutable revisions.
      The server never parses content, dereferences paths or URLs, or chooses latest. Follow
      next_actions to fetch content, disambiguate a revision, or retry after projection lag.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_locator_resolve
    output_schema Coordinator::Mcp::ArtifactSchemas.locator_resolve_result
    query "queries.development_artifact_locator_resolve"
  end
end

# frozen_string_literal: true

module Coordinator::Mcp::Tools
  class DevelopmentArtifactLocatorResolve < Coordinator::Mcp::QueryTool
    tool_name "development_artifact_locator_resolve"
    title "Resolve an exact Development Artifact locator"
    description <<~TEXT.squish
      Resolve an exact caller-normalized logical locator within one scope and source kind.
      Omit source_revision to receive zero, one, or multiple immutable revisions; the server
      never dereferences paths or URLs and never chooses a latest version implicitly.
    TEXT
    input_schema Coordinator::Mcp::Schemas.development_artifact_locator_resolve
    query "queries.development_artifact_locator_resolve"
  end
end

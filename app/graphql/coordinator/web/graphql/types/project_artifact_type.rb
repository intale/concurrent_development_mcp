# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectArtifactType < BaseObject
    graphql_name "ProjectArtifact"

    field :artifact, DevelopmentArtifactSummaryType, null: false
    field :content, DevelopmentArtifactContentType, null: false
  end
end

# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class ProjectArtifactRelationshipsType < BaseObject
    graphql_name "ProjectArtifactRelationships"

    field :artifact, DevelopmentArtifactSummaryType, null: false
    field :relationships, DevelopmentArtifactRelationConnectionType, null: false, connection: false
  end
end

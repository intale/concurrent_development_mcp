# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactSourceType < BaseObject
    graphql_name "DevelopmentArtifactSource"

    field :collector, String, null: false
    field :kind, DevelopmentArtifactSourceKindEnum, null: false
    field :locator, String, null: false
    field :observed_at, String, null: false
    field :revision, String, null: true
  end
end

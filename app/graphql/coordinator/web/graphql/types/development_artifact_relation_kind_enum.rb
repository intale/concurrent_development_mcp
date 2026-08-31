# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactRelationKindEnum < BaseEnum
    graphql_name "DevelopmentArtifactRelationKind"

    Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_RELATION_KINDS.each do |kind|
      value kind.upcase, value: kind
    end
  end
end

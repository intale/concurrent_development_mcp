# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactSourceKindEnum < BaseEnum
    graphql_name "DevelopmentArtifactSourceKind"

    Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_SOURCE_KINDS.each do |kind|
      value kind.upcase, value: kind
    end
  end
end

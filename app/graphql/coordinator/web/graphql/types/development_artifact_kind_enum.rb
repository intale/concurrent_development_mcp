# frozen_string_literal: true

module Coordinator::Web::Graphql::Types
  class DevelopmentArtifactKindEnum < BaseEnum
    graphql_name "DevelopmentArtifactKind"

    Coordinator::Shared::Types::DEVELOPMENT_ARTIFACT_KINDS.each do |kind|
      value kind.upcase, value: kind
    end
  end
end

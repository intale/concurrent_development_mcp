# frozen_string_literal: true

module Coordinator::Shared
  class DevelopmentArtifactRelationDefinitionV1 < Value
    attribute :relation, Types::DevelopmentArtifactRelationKind
    attribute :target_kinds, Types::Array.of(Types::DevelopmentArtifactCanonicalTargetKind)
    attribute :inverse, Types::String
    attribute :transitive, Types::Strict::Bool
    attribute :supersedable, Types::Strict::Bool
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationAttributesV1 < Value
      attribute :path, Types::DevelopmentArtifactRelationPath.optional
      attribute? :fragment, Types::DevelopmentArtifactRelationFragment.optional
      attribute? :normalized_locator, Types::DevelopmentArtifactSourceLocator.optional
    end
  end
end

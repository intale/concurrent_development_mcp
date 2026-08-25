# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationAttributesV1 < Value
      attribute :path, Types::DevelopmentArtifactRelationPath.optional
    end
  end
end

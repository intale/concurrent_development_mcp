# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationTargetV1 < Value
      attribute :kind, Types::DevelopmentArtifactTargetKind
      attribute :id, Types::DevelopmentArtifactTargetId
    end
  end
end

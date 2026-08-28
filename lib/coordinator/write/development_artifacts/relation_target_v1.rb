# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationTargetV1 < Value
      attribute :kind, Types::DevelopmentArtifactTargetKind
      attribute :id, Types::DevelopmentArtifactTargetId
      attribute? :status, Types::DevelopmentArtifactTargetStatus.optional
      attribute? :name, Types::SkillName.optional
      attribute? :scope, Types::SkillScope.optional
    end
  end
end

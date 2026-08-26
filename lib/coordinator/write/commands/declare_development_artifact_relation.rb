# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class DeclareDevelopmentArtifactRelation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :artifact_relation, DevelopmentArtifacts::RelationV1
      attribute? :supersedes_relation_id, Types::DevelopmentArtifactRelationId.optional
      attribute? :supersession_reason, Types::DevelopmentArtifactRelationSupersessionReason.optional
    end
  end
end

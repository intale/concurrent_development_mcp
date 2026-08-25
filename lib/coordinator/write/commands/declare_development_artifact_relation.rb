# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class DeclareDevelopmentArtifactRelation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :artifact_relation, DevelopmentArtifacts::RelationV1
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactRelationDeclaredV1 < Base
      contract type: "DevelopmentArtifactRelationDeclared", version: 1

      attribute :artifact_relation, DevelopmentArtifacts::RelationV1
      attribute :declared_at, Types::Timestamp
    end
  end
end

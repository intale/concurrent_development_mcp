# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactRelationSupersededV2 < Base
      contract type: "DevelopmentArtifactRelationSuperseded", version: 2

      attribute :relation_id, Types::DevelopmentArtifactRelationId
      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute? :replacement_relation_id, Types::DevelopmentArtifactRelationId.optional
      attribute :reason, Types::DevelopmentArtifactRelationSupersessionReason
    end
  end
end

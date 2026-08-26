# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactRelationSupersededV1 < Base
      contract type: "DevelopmentArtifactRelationSuperseded", version: 1

      attribute :source_artifact_id, Types::DevelopmentArtifactId
      attribute :superseded_relation_id, Types::DevelopmentArtifactRelationId
      attribute :replacement_relation_id, Types::DevelopmentArtifactRelationId
      attribute :reason, Types::DevelopmentArtifactRelationSupersessionReason
      attribute :superseded_at, Types::Timestamp
    end
  end
end

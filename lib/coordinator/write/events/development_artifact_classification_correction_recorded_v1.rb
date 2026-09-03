# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactClassificationCorrectionRecordedV1 < Base
      contract type: "DevelopmentArtifactClassificationCorrectionRecorded", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute? :observation_id, Types::DevelopmentArtifactObservationId.optional
      attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 1_000)
    end
  end
end

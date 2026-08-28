# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactClassificationCorrectedV1 < Base
      contract type: "DevelopmentArtifactClassificationCorrected", version: 1

      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 1_000)
      attribute :corrected_at, Types::Timestamp
    end
  end
end

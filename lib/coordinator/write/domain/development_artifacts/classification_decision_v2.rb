# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class ClassificationDecisionV2 < Value
        attribute :observation_id, Types::DevelopmentArtifactObservationId
        attribute :artifact_id, Types::DevelopmentArtifactId
        attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
        attribute :title, Types::DevelopmentArtifactTitle
        attribute :kind, Types::DevelopmentArtifactKind
        attribute :labels, Types::DevelopmentArtifactLabels
        attribute :event_plan, EventPlan.optional
        attribute? :fact_event_ids, Types::Array.of(Types::UuidV7)
        attribute :outcome, Types::String.enum("corrected", "existing")
      end
    end
  end
end

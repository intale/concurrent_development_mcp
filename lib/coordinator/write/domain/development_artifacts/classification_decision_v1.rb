# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class ClassificationDecisionV1 < Value
        attribute :observation, Events::DevelopmentArtifactObservedV1
        attribute :correction, Events::DevelopmentArtifactClassificationCorrectedV1.optional
        attribute :classification_revision, Types::DevelopmentArtifactClassificationRevision
        attribute :title, Types::DevelopmentArtifactTitle
        attribute :kind, Types::DevelopmentArtifactKind
        attribute :labels, Types::DevelopmentArtifactLabels
        attribute :event_plan, EventPlan.optional
        attribute :outcome, Types::String.enum("corrected", "existing")
      end
    end
  end
end

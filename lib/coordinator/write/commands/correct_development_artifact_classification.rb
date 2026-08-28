# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CorrectDevelopmentArtifactClassification < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :expected_revision, Types::DevelopmentArtifactClassificationRevision
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 1_000)
    end
  end
end

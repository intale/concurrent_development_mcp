# frozen_string_literal: true

module Coordinator::Write
  module Domain
    module DevelopmentArtifacts
      class GranularCaptureDecisionV1 < Value
        attribute :artifact, Coordinator::Write::DevelopmentArtifacts::ArtifactV2
        attribute :observation, Coordinator::Write::DevelopmentArtifacts::ArtifactObservationV1
        attribute :artifact_id, Types::DevelopmentArtifactId
        attribute :observation_id, Types::DevelopmentArtifactObservationId
        attribute :event_plan, EventPlan
        attribute :fact_event_ids, Types::Array.of(Types::UuidV7)
        attribute :outcome, Types::String.enum("created")
      end
    end
  end
end

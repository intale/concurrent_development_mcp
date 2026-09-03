# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactObservationFactLinkedV1 < Base
      contract type: "DevelopmentArtifactObservationFactLinked", version: 1

      attribute :observation_id, Types::DevelopmentArtifactObservationId
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :role, Types::Identifier
      attribute :observed_fact, EventReference
    end
  end
end

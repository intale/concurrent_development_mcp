# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactObservedV1 < Base
      contract type: "DevelopmentArtifactObserved", version: 1

      attribute :observation, DevelopmentArtifacts::ArtifactObservationV1
      attribute :recorded_at, Types::Timestamp
    end
  end
end

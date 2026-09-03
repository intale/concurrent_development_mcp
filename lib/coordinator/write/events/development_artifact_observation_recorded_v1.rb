# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactObservationRecordedV1 < Base
      contract type: "DevelopmentArtifactObservationRecorded", version: 1

      attribute :observation_id, Types::DevelopmentArtifactObservationId
    end
  end
end

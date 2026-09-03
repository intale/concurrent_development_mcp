# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactObservationFactLink < ApplicationRecord
    self.primary_key = "link_event_id"

    belongs_to :observation,
               class_name: "Coordinator::Read::DevelopmentArtifactObservation",
               foreign_key: "observation_id",
               inverse_of: :fact_links,
               optional: true

    belongs_to :artifact,
               class_name: "Coordinator::Read::DevelopmentArtifact",
               foreign_key: "artifact_id",
               optional: true
  end
end

# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactObservation < ApplicationRecord
    self.primary_key = "observation_id"

    belongs_to :artifact,
               class_name: "Coordinator::Read::DevelopmentArtifact",
               foreign_key: "artifact_id",
               inverse_of: :observations,
               optional: true
  end
end

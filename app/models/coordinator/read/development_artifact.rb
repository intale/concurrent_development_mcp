# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifact < ApplicationRecord
    self.primary_key = "artifact_id"

    has_many :relations,
             class_name: "Coordinator::Read::DevelopmentArtifactRelation",
             foreign_key: "source_artifact_id",
             inverse_of: :source_artifact,
             dependent: :delete_all

    has_many :observations,
             class_name: "Coordinator::Read::DevelopmentArtifactObservation",
             foreign_key: "artifact_id",
             inverse_of: :artifact,
             dependent: :delete_all
  end
end

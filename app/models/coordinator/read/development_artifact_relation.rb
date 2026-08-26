# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelation < ApplicationRecord
    self.primary_key = "relation_id"

    belongs_to :source_artifact,
               class_name: "Coordinator::Read::DevelopmentArtifact",
               foreign_key: "source_artifact_id",
               inverse_of: :relations,
               optional: true

    has_one :supersession,
            class_name: "Coordinator::Read::DevelopmentArtifactRelationSupersession",
            foreign_key: "superseded_relation_id",
            inverse_of: :relation,
            dependent: :delete
  end
end

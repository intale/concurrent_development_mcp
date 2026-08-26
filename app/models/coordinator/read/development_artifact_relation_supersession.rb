# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactRelationSupersession < ApplicationRecord
    self.primary_key = "superseded_relation_id"

    belongs_to :relation,
               class_name: "Coordinator::Read::DevelopmentArtifactRelation",
               foreign_key: "superseded_relation_id",
               inverse_of: :supersession,
               optional: true
  end
end

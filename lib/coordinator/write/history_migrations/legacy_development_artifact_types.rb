# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    module LegacyDevelopmentArtifactTypes
      ArtifactId = Types::String.constrained(format: /\Aartifact:v1:[0-9a-f]{64}\z/)
      ObservationId = Types::String.constrained(
        format: /\Aartifact-observation:v1:[0-9a-f]{64}\z/
      )
      RelationId = Types::String.constrained(format: /\Aartifact-relation:v1:[0-9a-f]{64}\z/)
    end
  end
end

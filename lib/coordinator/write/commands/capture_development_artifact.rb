# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CaptureDevelopmentArtifact < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :artifact, DevelopmentArtifacts::ArtifactV1
      attribute :observation, DevelopmentArtifacts::ArtifactObservationV1
    end
  end
end

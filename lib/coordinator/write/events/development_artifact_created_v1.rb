# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactCreatedV1 < Base
      contract type: "DevelopmentArtifactCreated", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
    end
  end
end

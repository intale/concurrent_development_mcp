# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactCapturedV1 < Base
      contract type: "DevelopmentArtifactCaptured", version: 1

      attribute :artifact, DevelopmentArtifacts::ArtifactV1
      attribute :captured_at, Types::Timestamp
    end
  end
end

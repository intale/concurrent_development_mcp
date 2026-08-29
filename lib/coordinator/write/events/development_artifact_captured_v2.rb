# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactCapturedV2 < Base
      contract type: "DevelopmentArtifactCaptured", version: 2

      attribute :artifact, DevelopmentArtifacts::ArtifactV2
      attribute :captured_at, Types::Timestamp
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactKindChangedV1 < Base
      contract type: "DevelopmentArtifactKindChanged", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :kind, Types::DevelopmentArtifactKind
    end
  end
end

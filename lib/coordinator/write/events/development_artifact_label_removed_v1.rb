# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactLabelRemovedV1 < Base
      contract type: "DevelopmentArtifactLabelRemoved", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :label, Types::DevelopmentArtifactLabel
    end
  end
end

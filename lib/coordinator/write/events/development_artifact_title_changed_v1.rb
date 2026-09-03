# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactTitleChangedV1 < Base
      contract type: "DevelopmentArtifactTitleChanged", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :title, Types::DevelopmentArtifactTitle
    end
  end
end

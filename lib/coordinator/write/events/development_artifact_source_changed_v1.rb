# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactSourceChangedV1 < Base
      contract type: "DevelopmentArtifactSourceChanged", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :source_kind, Types::DevelopmentArtifactSourceKind
      attribute :locator, Types::DevelopmentArtifactSourceLocator
      attribute :revision, Types::DevelopmentArtifactSourceRevision.optional
      attribute :observed_at, Types::Timestamp
    end
  end
end

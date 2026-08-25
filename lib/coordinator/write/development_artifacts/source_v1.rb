# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class SourceV1 < Value
      attribute :kind, Types::DevelopmentArtifactSourceKind
      attribute :locator, Types::DevelopmentArtifactSourceLocator
      attribute :revision, Types::DevelopmentArtifactSourceRevision.optional
      attribute :observed_at, Types::Timestamp
      attribute :collector, Types::DevelopmentArtifactCollector
    end
  end
end

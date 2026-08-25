# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ArtifactV1 < Value
      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :content, ContentV1
      attribute :source, SourceV1
    end
  end
end

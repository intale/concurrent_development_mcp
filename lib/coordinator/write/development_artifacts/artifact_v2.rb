# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ArtifactV2 < Value
      Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

      attribute :artifact_id, Types::DevelopmentArtifactId
      attribute :scope, Types::DevelopmentArtifactScope
      attribute :title, Types::DevelopmentArtifactTitle
      attribute :kind, Types::DevelopmentArtifactKind
      attribute :labels, Types::DevelopmentArtifactLabels
      attribute :content, Content
      attribute :source, SourceV1
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class UpdateChangesV1 < Value
      Content = Coordinator::Write::Content::TextV1 | Coordinator::Write::Content::BinaryV1

      attribute? :scope, Types::DevelopmentArtifactScope.optional
      attribute? :title, Types::DevelopmentArtifactTitle.optional
      attribute? :kind, Types::DevelopmentArtifactKind.optional
      attribute? :labels, Types::DevelopmentArtifactLabels.optional
      attribute? :content, Content.optional
      attribute? :source, SourceV1.optional
    end
  end
end

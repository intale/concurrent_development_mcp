# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DevelopmentArtifactContentChangedV1 < Base
      contract type: "DevelopmentArtifactContentChanged", version: 1

      attribute :artifact_id, Types::DevelopmentArtifactId
      # The representation is text for UTF-8 and Base64 for binary content. The
      # encoding and all derived descriptors live in Metadata::ContentV1.
      attribute :content, Types::String
    end
  end
end

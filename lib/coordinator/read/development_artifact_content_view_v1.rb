# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactContentViewV1 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
    attribute :encoding, Types::DevelopmentArtifactEncoding
    attribute :media_type, Types::DevelopmentArtifactMediaType
    attribute :text, Types::String.optional
    attribute :base64, Types::DevelopmentArtifactContentBase64.optional
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::DevelopmentArtifactByteSize
  end
end

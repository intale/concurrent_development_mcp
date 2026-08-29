# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactBinaryContentViewV2 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
    attribute :encoding, Types::String.enum("binary")
    attribute :media_type, Types::DevelopmentArtifactMediaType
    attribute :base64, Types::DevelopmentArtifactContentBase64
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::DevelopmentArtifactByteSize
  end
end

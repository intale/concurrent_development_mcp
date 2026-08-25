# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ContentV1 < Value
      attribute :encoding, Types::DevelopmentArtifactEncoding
      attribute :media_type, Types::DevelopmentArtifactMediaType
      attribute :content_base64, Types::DevelopmentArtifactContentBase64
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::DevelopmentArtifactByteSize
    end
  end
end

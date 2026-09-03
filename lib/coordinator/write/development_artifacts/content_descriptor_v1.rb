# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ContentDescriptorV1 < Value
      attribute :encoding, Types::DevelopmentArtifactEncoding
      attribute :media_type, Types::DevelopmentArtifactMediaType
      attribute :byte_size, Types::DevelopmentArtifactByteSize
      attribute :content_sha256, Types::Sha256Digest
    end
  end
end

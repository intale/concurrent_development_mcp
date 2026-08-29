# frozen_string_literal: true

module Coordinator::Read
  class DevelopmentArtifactTextContentViewV2 < Value
    attribute :artifact_id, Types::DevelopmentArtifactId
    attribute :encoding, Types::String.enum("utf-8")
    attribute :media_type, Types::DevelopmentArtifactMediaType
    attribute :text, Types::ContentText
    attribute :content_sha256, Types::Sha256Digest
    attribute :byte_size, Types::DevelopmentArtifactByteSize
  end
end

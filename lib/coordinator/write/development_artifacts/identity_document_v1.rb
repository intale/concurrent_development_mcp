# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class IdentityDocumentV1 < Value
      SCHEMA = "development-artifact-content-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :encoding, Types::DevelopmentArtifactEncoding
      attribute :media_type, Types::DevelopmentArtifactMediaType
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::DevelopmentArtifactByteSize
    end
  end
end

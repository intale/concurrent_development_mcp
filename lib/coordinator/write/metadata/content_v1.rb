# frozen_string_literal: true

module Coordinator::Write
  module Metadata
    class ContentV1 < EventMetadata
      attribute :encoding, Types::ContentEncoding
      attribute :media_type, Types::ContentMediaType
      attribute :byte_size, Types::ContentByteSize
      attribute :content_sha256, Types::Sha256Digest
    end
  end
end

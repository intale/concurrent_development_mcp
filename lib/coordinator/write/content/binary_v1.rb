# frozen_string_literal: true

module Coordinator::Write
  module Content
    class BinaryV1 < Value
      attribute :encoding, Types::String.enum("binary")
      attribute :media_type, Types::ContentMediaType
      attribute :base64, Types::ContentBase64
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::ContentByteSize
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Content
    class TextV1 < Value
      attribute :encoding, Types::String.enum("utf-8")
      attribute :media_type, Types::ContentMediaType
      attribute :text, Types::ContentText
      attribute :content_sha256, Types::Sha256Digest
      attribute :byte_size, Types::ContentByteSize
    end
  end
end

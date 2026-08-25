# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ContentBuilder
      def call(attributes)
        encoding = attributes.fetch(:encoding)
        bytes = if encoding == "utf-8"
                  attributes.fetch(:text).dup.force_encoding(Encoding::BINARY)
        else
                  attributes.fetch(:base64).unpack1("m0")
        end

        ContentV1.new(
          encoding:,
          media_type: attributes.fetch(:media_type),
          content_base64: [ bytes ].pack("m0"),
          content_sha256: "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}",
          byte_size: bytes.bytesize
        )
      end
    end
  end
end

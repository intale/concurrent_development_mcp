# frozen_string_literal: true

module Coordinator::Write
  module Skills
    class AssetBuilder
      def call(attributes)
        bytes = attributes.fetch(:content_base64).unpack1("m0")

        AssetV1.new(
          path: attributes.fetch(:path),
          media_type: attributes.fetch(:media_type),
          executable: attributes.fetch(:executable),
          content_base64: [ bytes ].pack("m0"),
          content_sha256: "sha256:#{OpenSSL::Digest::SHA256.hexdigest(bytes)}",
          byte_size: bytes.bytesize
        )
      end
    end
  end
end

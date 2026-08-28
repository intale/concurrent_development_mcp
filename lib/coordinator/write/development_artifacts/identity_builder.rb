# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class IdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(content:)
        document = IdentityDocumentV1.new(
          schema: IdentityDocumentV1::SCHEMA,
          encoding: content.encoding,
          media_type: content.media_type,
          content_sha256: content.content_sha256,
          byte_size: content.byte_size
        )
        digest = @canonical_json.sha256(document.to_h).delete_prefix("sha256:")

        "artifact:v1:#{digest}"
      end
    end
  end
end

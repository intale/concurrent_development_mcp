# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class IdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(scope:, source:, content:)
        document = IdentityDocumentV1.new(
          schema: IdentityDocumentV1::SCHEMA,
          scope:,
          source_kind: source.kind,
          source_locator: source.locator,
          content_sha256: content.content_sha256
        )
        digest = @canonical_json.sha256(document.to_h).delete_prefix("sha256:")

        "artifact:v1:#{digest}"
      end
    end
  end
end

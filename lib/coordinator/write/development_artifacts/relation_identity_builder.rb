# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class RelationIdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(source_artifact_id:, relation:, target:, attributes:)
        document = RelationIdentityDocumentV1.new(
          schema: RelationIdentityDocumentV1::SCHEMA,
          source_artifact_id:,
          relation:,
          target:,
          attributes:
        )
        digest = @canonical_json.sha256(document.to_h).delete_prefix("sha256:")

        "artifact-relation:v1:#{digest}"
      end
    end
  end
end

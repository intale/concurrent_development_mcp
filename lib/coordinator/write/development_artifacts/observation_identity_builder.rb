# frozen_string_literal: true

module Coordinator::Write
  module DevelopmentArtifacts
    class ObservationIdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(artifact_id:, scope:, source:)
        document = ObservationIdentityDocumentV1.new(
          schema: ObservationIdentityDocumentV1::SCHEMA,
          artifact_id:,
          scope:,
          source_kind: source.kind,
          source_locator: source.locator,
          source_revision: source.revision,
          source_observed_at: source.observed_at,
          source_collector: source.collector
        )
        digest = @canonical_json.sha256(document.to_h).delete_prefix("sha256:")

        "artifact-observation:v1:#{digest}"
      end
    end
  end
end

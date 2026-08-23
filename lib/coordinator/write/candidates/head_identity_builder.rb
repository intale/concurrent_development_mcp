# frozen_string_literal: true

module Coordinator::Write
  module Candidates
    class HeadIdentityBuilder
      def initialize(
        canonical_json: CanonicalJson.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @canonical_json = canonical_json
        @compound_marker_builder = compound_marker_builder
      end

      def call(repository_id:, object_format:, head_commit_oid:)
        document = HeadIdentityDocumentV1.new(
          schema: HeadIdentityDocumentV1::SCHEMA,
          repository_id:,
          object_format:,
          head_commit_oid:
        )
        marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "candidate-head-identity",
            components: [
              "repository:#{repository_id}",
              "object-format:#{object_format}",
              "head-commit-oid:#{head_commit_oid}"
            ]
          )
        )

        HeadIdentityV1.new(
          document:,
          registry_id: @canonical_json.sha256(document.to_h),
          marker: marker.marker
        )
      end
    end
  end
end

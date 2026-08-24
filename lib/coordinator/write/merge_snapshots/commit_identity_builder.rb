# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshots
    class CommitIdentityBuilder
      def initialize(
        canonical_json: CanonicalJson.new,
        compound_marker_builder: CompoundMarkerBuilder.new
      )
        @canonical_json = canonical_json
        @compound_marker_builder = compound_marker_builder
      end

      def call(repository_id:, object_format:, merge_commit_oid:)
        document = CommitIdentityDocumentV1.new(
          schema: CommitIdentityDocumentV1::SCHEMA,
          repository_id:,
          object_format:,
          merge_commit_oid:
        )
        marker = @compound_marker_builder.call(
          CompoundMarkerDefinitionV1.new(
            purpose: "merge-snapshot-commit-identity",
            components: [
              "repository:#{repository_id}",
              "object-format:#{object_format}",
              "merge-commit-oid:#{merge_commit_oid}"
            ]
          )
        )

        CommitIdentityV1.new(
          document:,
          registry_id: @canonical_json.sha256(document.to_h),
          marker: marker.marker
        )
      end
    end
  end
end

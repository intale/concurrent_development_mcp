# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class VerifiedDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(merge_snapshot_id:, snapshot_digest:, policy_version:, selected_verification:)
        @canonical_json.sha256(
          VerifiedDigestDocumentV1.new(
            schema: "merge-snapshot-verified/v1",
            merge_snapshot_id:,
            snapshot_digest:,
            policy_version:,
            selected_verification:
          ).to_h
        )
      end
    end
  end
end

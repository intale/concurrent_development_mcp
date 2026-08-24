# frozen_string_literal: true

module Coordinator::Write
  module MergeSnapshotVerifications
    class VerificationInputDigest
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(policy_version:, snapshot:, assessment:)
        @canonical_json.sha256(document(policy_version:, snapshot:, assessment:).to_h)
      end

      def document(policy_version:, snapshot:, assessment:)
        VerificationInputDocumentV1.new(
          schema: "merge-snapshot-verification-input/v1",
          policy_version:,
          snapshot:,
          assessment:
        )
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ReleaseDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(release_set_id:, change_set_id:, ordered_members:, policy_version:)
        document = ReleaseDigestDocumentV1.new(
          schema: "release-set/v1",
          release_set_id:,
          change_set_id:,
          ordered_members:,
          policy_version:
        )
        @canonical_json.sha256(document.to_h)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class ActivationDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(release_set_id:, release_digest:, verification_event:, verification_digest:, activation_point:, policy_version:)
        document = ActivationDigestDocumentV1.new(
          schema: "release-set-activation/v1",
          release_set_id:,
          release_digest:,
          verification_event:,
          verification_digest:,
          activation_point:,
          policy_version:
        )
        @canonical_json.sha256(document.to_h)
      end
    end
  end
end

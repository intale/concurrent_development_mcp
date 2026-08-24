# frozen_string_literal: true

module Coordinator::Write
  module ReleaseSets
    class CompletionDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(release_set_id:, release_digest:, outcome:, source_event:, compensation_evidence:, rule_version:)
        document = CompletionDigestDocumentV1.new(
          schema: "release-set-completion/v1",
          release_set_id:,
          release_digest:,
          outcome:,
          source_event:,
          compensation_evidence:,
          rule_version:
        )
        @canonical_json.sha256(document.to_h)
      end
    end
  end
end

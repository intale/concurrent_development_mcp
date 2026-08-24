# frozen_string_literal: true

module Coordinator::Write
  module MergeAuthorizations
    class DecisionDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(policy_version:, input_digest:, snapshot_binding:, expected_impact_policy:, evaluation:, outcome:)
        document = DecisionDocumentV1.new(
          schema: DecisionDocumentV1::SCHEMA,
          policy_version:,
          input_digest:,
          snapshot_binding:,
          expected_impact_policy:,
          evaluation:,
          outcome:
        )
        @canonical_json.sha256(document.to_h)
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class ValidityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(source:, target:, reasons:, policy:, rule_version:)
        document = ValidityDocumentV1.new(
          schema: ValidityDocumentV1::SCHEMA,
          source_candidate: source.subject,
          target_candidate: target.subject,
          reasons:,
          required_evidence: policy.required_evidence,
          enforcement: policy.enforcement,
          policy:,
          rule_version:
        )
        ValidityV1.new(document:, digest: @canonical_json.sha256(document.to_h))
      end
    end
  end
end

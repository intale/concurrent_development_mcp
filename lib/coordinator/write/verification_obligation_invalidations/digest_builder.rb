# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationInvalidations
    class DigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(obligation_event:, invalidated_policy:, superseding_partition_event:, previous_status:,
               previous_terminal_event:, rule_version:)
        document = DigestDocumentV1.new(
          schema: "verification-obligation-invalidation/v1",
          obligation_event:,
          invalidated_policy:,
          superseding_partition_event:,
          previous_status:,
          previous_terminal_event:,
          reason: "policy_partition_advanced",
          rule_version:
        )
        @canonical_json.sha256(document.to_h)
      end
    end
  end
end

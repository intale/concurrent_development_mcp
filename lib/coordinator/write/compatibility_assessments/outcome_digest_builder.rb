# frozen_string_literal: true

module Coordinator::Write
  module CompatibilityAssessments
    class OutcomeDigestBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def satisfied(obligation:, selected_evidence:)
        @canonical_json.sha256(
          schema: "verification-obligation-satisfied/v1",
          obligation_id: obligation.obligation_id,
          obligation_validity_input_digest: obligation.validity_input_digest,
          policy_partition_event_id: obligation.policy.partition_event.event_id,
          policy_head_event_id: obligation.policy.head.event.event_id,
          required_evidence: obligation.required_evidence,
          selected_evidence: selected_evidence.map(&:to_h)
        )
      end

      def failed(obligation:, triggering_evidence:)
        @canonical_json.sha256(
          schema: "verification-obligation-failed/v1",
          obligation_id: obligation.obligation_id,
          obligation_validity_input_digest: obligation.validity_input_digest,
          policy_partition_event_id: obligation.policy.partition_event.event_id,
          policy_head_event_id: obligation.policy.head.event.event_id,
          triggering_evidence: triggering_evidence.to_h
        )
      end
    end
  end
end

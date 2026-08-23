# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class IdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def registry_sweep(policy_partition_event:, policy_head:, rule_version:)
        document = RegistrySweepIdentityDocumentV1.new(
          schema: "candidate-impact-registry-sweep-identity/v1",
          policy_partition_event:,
          policy_head:,
          rule_version:
        )
        "candidate-impact-registry-sweep-v1:#{digest(document)}"
      end

      def pair_scan(source_registration:, direction:, policy_partition_event:, policy_head:, rule_version:)
        document = PairScanIdentityDocumentV1.new(
          schema: "candidate-impact-pair-scan-identity/v1",
          source_registration:,
          direction:,
          policy_partition_event:,
          policy_head:,
          rule_version:
        )
        "candidate-impact-pair-scan-v1:#{digest(document)}"
      end

      def progress(checkpoint_event:, rule_version:)
        document = ProgressIdentityDocumentV1.new(
          schema: "candidate-impact-scan-progress-identity/v1",
          checkpoint_event:,
          rule_version:
        )
        "candidate-impact-scan-progress-v1:#{digest(document)}"
      end

      private

      def digest(document)
        @canonical_json.sha256(document.to_h).delete_prefix("sha256:")
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class IdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def scan(superseding_partition_event:, rule_version:)
        document = ScanIdentityDocumentV1.new(
          schema: "verification-obligation-validity-scan-identity/v1",
          superseding_partition_event:,
          rule_version:
        )
        Types::InternalCommandId["internal:verification-obligation-validity-scan-v1:#{digest(document)}"]
      end

      def progress(checkpoint_event:, rule_version:)
        document = ProgressIdentityDocumentV1.new(
          schema: "verification-obligation-validity-progress-identity/v1",
          checkpoint_event:,
          rule_version:
        )
        Types::InternalCommandId["internal:verification-obligation-validity-progress-v1:#{digest(document)}"]
      end

      private

      def digest(document)
        @canonical_json.sha256(document.to_h).delete_prefix("sha256:")
      end
    end
  end
end

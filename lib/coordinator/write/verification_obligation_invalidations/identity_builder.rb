# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationInvalidations
    class IdentityBuilder
      def initialize(canonical_json: CanonicalJson.new)
        @canonical_json = canonical_json
      end

      def call(obligation_event:, superseding_partition_event:, rule_version:)
        document = IdentityDocumentV1.new(
          schema: "verification-obligation-invalidation-identity/v1",
          obligation_event:,
          superseding_partition_event:,
          rule_version:
        )
        Types::InternalCommandId["internal:verification-obligation-invalidation-v1:#{digest(document)}"]
      end

      private

      def digest(document)
        @canonical_json.sha256(document.to_h).delete_prefix("sha256:")
      end
    end
  end
end

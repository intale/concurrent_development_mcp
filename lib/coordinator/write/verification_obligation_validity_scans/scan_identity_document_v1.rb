# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class ScanIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("verification-obligation-validity-scan-identity/v1")
      attribute :superseding_partition_event, EventReference
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end

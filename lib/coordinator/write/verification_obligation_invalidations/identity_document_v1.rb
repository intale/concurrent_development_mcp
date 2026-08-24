# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationInvalidations
    class IdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("verification-obligation-invalidation-identity/v1")
      attribute :obligation_event, EventReference
      attribute :superseding_partition_event, EventReference
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end

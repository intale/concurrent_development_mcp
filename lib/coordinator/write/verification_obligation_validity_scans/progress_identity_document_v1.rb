# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class ProgressIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("verification-obligation-validity-progress-identity/v1")
      attribute :checkpoint_event, EventReference
      attribute :rule_version, Types::VerificationObligationInvalidationRuleVersion
    end
  end
end

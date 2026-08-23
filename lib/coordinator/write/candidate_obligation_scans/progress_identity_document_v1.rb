# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class ProgressIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("candidate-impact-scan-progress-identity/v1")
      attribute :checkpoint_event, EventReference
      attribute :rule_version, Types::CandidateImpactScanRuleVersion
    end
  end
end

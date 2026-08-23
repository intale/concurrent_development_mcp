# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class PairScanIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("candidate-impact-pair-scan-identity/v1")
      attribute :source_registration, EventReference
      attribute :direction, Types::CandidateImpactQueryDirection
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :rule_version, Types::CandidateImpactPairScanRuleVersion
    end
  end
end

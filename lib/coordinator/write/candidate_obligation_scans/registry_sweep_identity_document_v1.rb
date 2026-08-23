# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class RegistrySweepIdentityDocumentV1 < Value
      attribute :schema, Types::String.enum("candidate-impact-registry-sweep-identity/v1")
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :rule_version, Types::CandidateImpactRegistrySweepRuleVersion
    end
  end
end

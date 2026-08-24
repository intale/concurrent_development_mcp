# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligations
    class IdentityDocumentV1 < Value
      SCHEMA = "candidate-compatibility-obligation-identity/v1"

      attribute :schema, Types::String.enum(SCHEMA)
      attribute :rule_version, Types::CandidateCompatibilityObligationRuleVersion
      attribute :source_surface, EventReference
      attribute :target_surface, EventReference
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
    end
  end
end

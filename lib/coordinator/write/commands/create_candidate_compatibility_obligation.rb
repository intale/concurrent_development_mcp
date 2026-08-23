# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CreateCandidateCompatibilityObligation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :obligation_id, Types::Identifier
      attribute :source_registration, EventReference
      attribute :target_registration, EventReference
      attribute :policy_partition_event, EventReference
      attribute :policy_head, Decisions::DecisionHeadV1
      attribute :rule_version, Types::CandidateCompatibilityObligationRuleVersion
    end
  end
end

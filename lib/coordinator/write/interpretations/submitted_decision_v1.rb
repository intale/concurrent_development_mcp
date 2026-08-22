# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class SubmittedDecisionV1 < Value
      attribute :statement_kind, Types::StatementKind
      attribute :topic_id, Types::Identifier
      attribute :effect, Types::DecisionEffect.optional
      attribute :modality, Types::DecisionModality.optional
      attribute :value, DecisionValueV1
      attribute :scope, DecisionScopeV1.optional
      attribute :conditions, DecisionConditionsV1
      attribute :validity, DecisionValidityV1
      attribute :authority, DecisionAuthorityV1
      attribute :enforcement, DecisionEnforcementV1
      attribute :relations, DecisionRelationsV1
    end
  end
end

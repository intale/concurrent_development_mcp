# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionDefinitionDocumentV1 < Value
      attribute :schema, Types::String.enum("decision-definition/v1")
      attribute :statement_kind, Types::StatementKind
      attribute :topic, Interpretations::TopicDefinitionV1
      attribute :effect, Types::DecisionEffect
      attribute :modality, Types::DecisionModality
      attribute :value, Interpretations::DecisionValueV1
      attribute :scope, Interpretations::DecisionScopeV1
      attribute :conditions, Interpretations::DecisionConditionsV1
      attribute :validity, Interpretations::DecisionValidityV1
      attribute :authority, Interpretations::DecisionAuthorityV1
      attribute :enforcement, Interpretations::DecisionEnforcementV1
      attribute :relations, Interpretations::DecisionRelationsV1

      def topic_root
        topic.topic_id.split(".", 2).first
      end
    end
  end
end

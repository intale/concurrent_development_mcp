# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionSlotDocumentV1 < Value
      attribute :schema, Types::String.enum("decision-slot/v1")
      attribute :topic_id, Types::SupportedInterpretationTopic
      attribute :exact_scope, Interpretations::DecisionScopeV1
      attribute :exact_conditions, Interpretations::DecisionConditionsV1
      attribute :conflict_dimension, Types::Identifier
      attribute :resolution_strategy, Types::ResolutionStrategy
    end
  end
end

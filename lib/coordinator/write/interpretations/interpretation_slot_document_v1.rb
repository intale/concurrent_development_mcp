# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationSlotDocumentV1 < Value
      attribute :schema, Types::String.enum("interpretation-adjudication-slot/v1")
      attribute :source_message_id, Types::Identifier
      attribute :topic_id, Types::SupportedInterpretationTopic
      attribute :exact_scope, DecisionScopeV1
      attribute :conflict_dimension, Types::Identifier
      attribute :resolution_strategy, Types::ResolutionStrategy
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AdjudicateDecisionInterpretation < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :source_message_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :action, Types::InterpretationAdjudicationAction
      attribute :rationale, Interpretations::AdjudicationRationaleV1
      attribute :clarification, Interpretations::AdjudicationClarificationV1.optional
    end
  end
end

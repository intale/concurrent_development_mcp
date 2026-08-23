# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ReconstructionV1 < Value
      Advancement = EventReference

      attribute :before_context, DecisionContexts::ContextV1
      attribute :after_context, DecisionContexts::ContextV1
      attribute :before_evaluation, AgentChoices::PolicyEvaluationV1
      attribute :after_evaluation, AgentChoices::PolicyEvaluationV1
      attribute :source_advancements,
                Types::Array.of(Advancement).constrained(min_size: 1, max_size: 5)
      attribute :source_already_observed, Types::Bool
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module AgentChoices
    class ChoiceAssessmentV1 < Value
      Head = Decisions::DecisionHeadV1

      attribute :basis, Types::AgentChoiceAssessmentBasis
      attribute :based_on_decisions, Types::Array.of(Head).constrained(max_size: 1)
      Warning = Types::String.constrained(min_size: 1, max_size: 500)

      attribute :warnings, Types::Array.of(Warning).constrained(max_size: 10)
    end
  end
end

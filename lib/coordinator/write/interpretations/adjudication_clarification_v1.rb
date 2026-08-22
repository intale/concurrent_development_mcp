# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class AdjudicationClarificationV1 < Value
      Question = ClarificationQuestionV1

      attribute :status, Types::InterpretationClarificationStatus
      attribute :questions, Types::Array.of(Question).constrained(min_size: 1, max_size: 20)
    end
  end
end

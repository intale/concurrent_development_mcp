# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationAssessmentV1 < Value
      Question = ClarificationQuestionV1

      attribute :status, Types::InterpretationAssessmentStatus
      attribute :reasons, Types::InterpretationReasons
      attribute :questions, Types::Array.of(Question).constrained(max_size: 20)
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionClarificationRequiredV1 < Base
      contract type: "DecisionClarificationRequired", version: 1

      Question = Interpretations::ClarificationQuestionV1

      attribute :interpretation_id, Types::Identifier
      attribute :source_message_id, Types::Identifier
      attribute :status, Types::InterpretationAssessmentStatus
      attribute :origin, Types::InterpretationClarificationOrigin
      attribute :reasons, Types::InterpretationReasons
      attribute :questions, Types::Array.of(Question).constrained(min_size: 1, max_size: 20)
      attribute :rationale, Interpretations::AdjudicationRationaleV1.optional
      attribute :required_at, Types::Timestamp
    end
  end
end

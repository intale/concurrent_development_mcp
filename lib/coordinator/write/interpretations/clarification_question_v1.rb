# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class ClarificationQuestionV1 < Value
      attribute :field, Types::Identifier
      attribute :prompt, Types::InterpretationDescription
      attribute :options, Types::InterpretationOptions
    end
  end
end

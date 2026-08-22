# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class InterpretationAmbiguityV1 < Value
      attribute :field, Types::Identifier
      attribute :code, Types::Identifier
      attribute :description, Types::InterpretationDescription
      attribute :options, Types::InterpretationOptions
    end
  end
end

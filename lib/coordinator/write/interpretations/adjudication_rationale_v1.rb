# frozen_string_literal: true

module Coordinator::Write
  module Interpretations
    class AdjudicationRationaleV1 < Value
      attribute :code, Types::Identifier
      attribute :summary, Types::InterpretationDescription
    end
  end
end

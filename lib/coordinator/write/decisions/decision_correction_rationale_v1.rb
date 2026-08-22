# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionCorrectionRationaleV1 < Value
      attribute :code, Types::Identifier
      attribute :summary, Types::InterpretationDescription
    end
  end
end

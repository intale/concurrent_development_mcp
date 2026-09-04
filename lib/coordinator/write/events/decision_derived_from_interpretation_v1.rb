# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionDerivedFromInterpretationV1 < Base
      contract type: "DecisionDerivedFromInterpretation", version: 1

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Events
    class DecisionActivatedV2 < Base
      contract type: "DecisionActivated", version: 2

      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :rationale, Types::InterpretationDescription
    end
  end
end

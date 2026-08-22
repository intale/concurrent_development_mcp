# frozen_string_literal: true

module Coordinator::Write
  module Decisions
    class DecisionActivationEvidenceV1 < Value
      attribute :decision_id, Types::Identifier
      attribute :interpretation_id, Types::Identifier
      attribute :event, EventReference
    end
  end
end

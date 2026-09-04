# frozen_string_literal: true

module Coordinator::Read
  module AgentChoiceImpacts
    class DecisionChangeSourceV1 < Value
      attribute :evidence, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute :changed_at, Types::Timestamp
    end
  end
end

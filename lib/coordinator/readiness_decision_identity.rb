# frozen_string_literal: true

module Coordinator
  class ReadinessDecisionIdentity < Value
    attribute :document, Types.Instance(ProcessDecisions::ReadinessV1)
    attribute :compound_marker, Types.Instance(CompoundMarker)
    attribute :command_id, Types::Identifier

    def readiness_decision_id
      command_id
    end
  end
end

# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class RepairTargetV1 < Value
      attribute :source_event, Types.Instance(PgEventstore::Event)
      attribute :decision_change, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV1
    end
  end
end

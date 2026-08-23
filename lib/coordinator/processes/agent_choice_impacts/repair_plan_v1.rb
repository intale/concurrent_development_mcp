# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class RepairPlanV1 < Value
      attribute :accepted_choice, Types.Instance(PgEventstore::Event)
      attribute :accepted_choice_reference, Coordinator::Write::EventReference
      attribute :targets, Types::Array.of(RepairTargetV1).constrained(max_size: 32)
    end
  end
end

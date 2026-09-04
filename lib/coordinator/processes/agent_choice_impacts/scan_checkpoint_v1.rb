# frozen_string_literal: true

module Coordinator::Processes
  module AgentChoiceImpacts
    class ScanCheckpointV1 < Value
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, Coordinator::Write::EventReference
      attribute :scan_id, Types::UuidV7
      attribute :decision_change, Coordinator::Write::AgentChoiceImpacts::DecisionChangeEvidenceV2
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::AgentChoiceImpactPageSize
      attribute :policy_version, Types::AgentChoiceImpactPolicyVersion
    end
  end
end

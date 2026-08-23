# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class DecisionChangeEvidenceV1 < Value
      Partition = Decisions::DecisionPartitionV1

      attribute :source_event, EventReference
      attribute :source_global_position, Types::GlobalPosition
      attribute :source_command_id, Types::Identifier
      attribute :source_actor, Commands::Actor
      attribute :decision_id, Types::Identifier
      attribute :change_kind, Types::DecisionChangeKind
      attribute :definition_digest, Types::Sha256Digest
      attribute :retroactivity, Types::RetroactivityKind
      attribute :affected_partitions, Types::Array.of(Partition).constrained(min_size: 1, max_size: 32)
      attribute :changed_at, Types::Timestamp
    end
  end
end

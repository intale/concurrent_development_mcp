# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class RenewWorkIntentionSet < Value
      Reference = Types.Instance(WorkIntentionFencedReferenceV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :intention_set_id, Types::UuidV7
      attribute :intentions, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
      attribute :ttl_seconds, Types::LeaseDurationSeconds
    end
  end
end

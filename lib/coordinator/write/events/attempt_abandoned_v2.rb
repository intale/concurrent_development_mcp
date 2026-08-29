# frozen_string_literal: true

module Coordinator::Write
  module Events
    class AttemptAbandonedV2 < Base
      Reference = LeaseReferenceV2

      contract type: "AttemptAbandoned", version: 2

      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :agent_id, Types::Identifier
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
      attribute :lease_set_id, Types::UuidV7.optional
      attribute :released_leases, Types::Array.of(Reference).constrained(max_size: 32)
      attribute :untouched_resource_ids, Types::Array.of(Types::ResourceId).constrained(max_size: 32)
      attribute :abandoned_at, Types::Timestamp
    end
  end
end

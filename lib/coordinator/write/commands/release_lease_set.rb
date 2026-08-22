# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ReleaseLeaseSet < Value
      Reference = Types.Instance(LeaseReleaseReferenceV1)

      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :change_set_id, Types::Identifier
      attribute :work_item_id, Types::Identifier
      attribute :attempt_id, Types::Identifier
      attribute :lease_set_id, Types::UuidV7
      attribute :leases, Types::Array.of(Reference).constrained(min_size: 1, max_size: 32)
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyWorkIntentionSetStateV1 < Value
      Membership = Types.Instance(LegacyWorkIntentionMembershipV1)

      attribute :source_set_id, Types::UuidV7
      attribute :reservation_event, Types.Instance(PgEventstore::Event)
      attribute :reservation, Events::WriteSetReservedV2
      attribute :memberships,
                Types::Array.of(Membership).constrained(
                  min_size: 1,
                  max_size: WorkIntentionPolicyV1::MAXIMUM_SET_SIZE
                )

      def membership(lease_id)
        memberships.find { _1.reference.lease_id == lease_id }
      end
    end
  end
end

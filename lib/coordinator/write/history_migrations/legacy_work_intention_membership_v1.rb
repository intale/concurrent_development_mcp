# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyWorkIntentionMembershipV1 < Value
      attribute :reference, LeaseReferenceV2
      attribute :membership_event, Types.Instance(PgEventstore::Event)
      attribute :acquisition_event, Types.Instance(PgEventstore::Event)
      attribute :acquisition, Events::ResourceLeaseAcquiredV2
    end
  end
end

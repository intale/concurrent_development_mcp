# frozen_string_literal: true

module Coordinator::Write
  class PreparedLeaseRenewalV1 < Value
    attribute :reference, Types.Instance(LeaseRenewalReferenceV1)
    attribute :event_id, Types::UuidV7
  end
end

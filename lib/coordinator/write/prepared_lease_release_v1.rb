# frozen_string_literal: true

module Coordinator::Write
  class PreparedLeaseReleaseV1 < Value
    attribute :reference, Types.Instance(LeaseReleaseReferenceV1)
    attribute :event_id, Types::UuidV7
  end
end

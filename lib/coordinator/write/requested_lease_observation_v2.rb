# frozen_string_literal: true

module Coordinator::Write
  class RequestedLeaseObservationV2 < Value
    attribute :prepared_target, Types.Instance(PreparedLeaseTargetV1)
    attribute :resource, Types.Instance(LeaseResourceV2)
    attribute :state, Types.Instance(Domain::ResourceLeases::State)
  end
end

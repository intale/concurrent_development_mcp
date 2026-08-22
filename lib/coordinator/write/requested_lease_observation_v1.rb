# frozen_string_literal: true

module Coordinator::Write
  class RequestedLeaseObservationV1 < Value
    attribute :prepared_resource, Types.Instance(PreparedLeaseResourceV1)
    attribute :state, Types.Instance(Domain::ResourceLeases::State)
  end
end

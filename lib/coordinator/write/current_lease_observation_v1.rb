# frozen_string_literal: true

module Coordinator::Write
  class CurrentLeaseObservationV1 < Value
    attribute :reference, Types.Instance(LeaseReferenceV1)
    attribute :state, Types.Instance(Domain::ResourceLeases::State)
  end
end

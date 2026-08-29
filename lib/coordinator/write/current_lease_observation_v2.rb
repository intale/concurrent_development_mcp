# frozen_string_literal: true

module Coordinator::Write
  class CurrentLeaseObservationV2 < Value
    attribute :reference, Types.Instance(LeaseReferenceV2)
    attribute :state, Types.Instance(Domain::ResourceLeases::State)
  end
end

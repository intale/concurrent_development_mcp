# frozen_string_literal: true

module Coordinator::Processes
  class LeaseExpirySource < Value
    Payload = Types.Instance(Coordinator::Write::Events::ResourceLeaseAcquiredV1) |
              Types.Instance(Coordinator::Write::Events::ResourceLeaseRenewedV1)

    attribute :event, Types.Instance(PgEventstore::Event)
    attribute :reference, Types.Instance(Coordinator::Write::EventReference)
    attribute :payload, Payload
  end
end

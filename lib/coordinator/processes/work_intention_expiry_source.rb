# frozen_string_literal: true

module Coordinator::Processes
  class WorkIntentionExpirySource < Value
    Payload = Types.Instance(Coordinator::Write::Events::ResourceWorkIntentionDeclaredV1) |
              Types.Instance(Coordinator::Write::Events::ResourceWorkIntentionRenewedV1)

    attribute :event, Types.Instance(PgEventstore::Event)
    attribute :reference, Types.Instance(Coordinator::Write::EventReference)
    attribute :payload, Payload
    attribute :state, Types.Instance(Coordinator::Write::Domain::WorkIntentions::State).optional.default(nil)
  end
end

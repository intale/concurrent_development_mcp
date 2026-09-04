# frozen_string_literal: true

module Coordinator::Processes
  class ChangeSetActivationSource < Value
    attribute :event, Types.Instance(PgEventstore::Event)
    attribute :reference, Types.Instance(Coordinator::Write::EventReference)
    attribute :payload,
              Types.Instance(Coordinator::Write::Events::ChangeSetActivatedV1) |
                Types.Instance(Coordinator::Write::Events::ChangeSetActivatedV2)
  end
end

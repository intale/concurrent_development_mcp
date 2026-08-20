# frozen_string_literal: true

module Coordinator
  class ChangeSetActivationSource < Value
    attribute :event, Types.Instance(PgEventstore::Event)
    attribute :reference, Types.Instance(EventReference)
    attribute :payload, Types.Instance(Events::ChangeSetActivatedV1)
    attribute :correlation_id, Types::Identifier
  end
end

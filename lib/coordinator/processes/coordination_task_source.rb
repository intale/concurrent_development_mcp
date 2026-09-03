# frozen_string_literal: true

module Coordinator::Processes
  class CoordinationTaskSource < Value
    attribute :event, Types.Instance(PgEventstore::Event)
    attribute :reference, Types.Instance(Coordinator::Write::EventReference)
    attribute :payload, Types.Instance(Coordinator::Write::Events::CoordinationTaskSubmittedV3)
  end
end

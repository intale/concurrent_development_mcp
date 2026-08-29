# frozen_string_literal: true

module Coordinator::Processes
  class CoordinationTaskSource < Value
    Submission = Types.Instance(Coordinator::Write::Events::CoordinationTaskSubmittedV1) |
                 Types.Instance(Coordinator::Write::Events::CoordinationTaskSubmittedV2)

    attribute :event, Types.Instance(PgEventstore::Event)
    attribute :reference, Types.Instance(Coordinator::Write::EventReference)
    attribute :payload, Submission
  end
end

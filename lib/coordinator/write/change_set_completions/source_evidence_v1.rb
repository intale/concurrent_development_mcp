# frozen_string_literal: true

module Coordinator::Write
  module ChangeSetCompletions
    class SourceEvidenceV1 < Value
      Payload = Events::WorkItemCompletedV1 | Events::ReleaseSetCompletedV1

      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, EventReference
      attribute :payload, Payload
    end
  end
end

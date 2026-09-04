# frozen_string_literal: true

module Coordinator::Write
  module ChangeSetCompletions
    class SourceEvidenceV1 < Value
      Payload = Events::WorkItemCompletedV1 |
                Events::WorkItemCompletedV2 |
                Events::ReleaseSetCompletedV2

      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :reference, EventReference
      attribute :payload, Payload
    end
  end
end

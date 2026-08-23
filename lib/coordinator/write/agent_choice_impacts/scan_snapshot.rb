# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ScanSnapshot < Value
      attribute :state, Types.Instance(Domain::AgentChoiceImpacts::ScanState)
      attribute :latest_revision, Types::StreamRevision.optional
      attribute :persisted_events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 4)
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module CommandLifecycle
    class Snapshot < Value
      attribute :state, Types.Instance(Domain::CommandLifecycles::State)
      attribute :latest_revision, Types::Integer.optional
      attribute :persisted_events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 2)
    end
  end
end

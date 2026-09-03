# frozen_string_literal: true

module Coordinator::Write
  module Tasks
    class Snapshot < Value
      attribute :state, Types.Instance(Domain::CoordinationTasks::State)
      attribute :latest_revision, Types::Integer.optional
      attribute :persisted_events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 8)
    end
  end
end

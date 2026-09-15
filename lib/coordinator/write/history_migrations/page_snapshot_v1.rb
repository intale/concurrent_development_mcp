# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageSnapshotV1 < Value
      attribute :state, Types.Instance(Domain::HistoryMigrationPages::State)
      attribute :physical_events, Types::Array.of(Types.Instance(PgEventstore::Event)).constrained(max_size: 7)
      attribute :latest_revision, Types::StreamRevision.optional

      def event(type)
        physical_events.find { _1.type == type }
      end
    end
  end
end

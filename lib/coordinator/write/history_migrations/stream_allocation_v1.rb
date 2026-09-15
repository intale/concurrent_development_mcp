# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class StreamAllocationV1 < Value
      attribute :target_stream, StreamReference
      attribute :allocation_event, Types.Instance(PgEventstore::Event)
      attribute :outcome, Types::String.enum("created", "existing")
    end
  end
end

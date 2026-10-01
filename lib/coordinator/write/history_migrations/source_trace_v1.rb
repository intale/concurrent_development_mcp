# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceTraceV1 < Value
      attribute :source_event_id, Types::UuidV7
      attribute :source_causation_id, Types::UuidV7.optional
      attribute :target_endpoint, EventReference.optional
      attribute :resolution_event, Types.Instance(PgEventstore::Event)
      attribute :outcome, Types::String.enum("created", "existing")
    end
  end
end

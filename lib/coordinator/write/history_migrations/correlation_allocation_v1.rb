# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CorrelationAllocationV1 < Value
      attribute :target_correlation_id, Types::UuidV7
      attribute :allocation_event, Types.Instance(PgEventstore::Event)
      attribute :outcome, Types::String.enum("created", "existing")
    end
  end
end

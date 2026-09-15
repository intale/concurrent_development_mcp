# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetWriteErrorV1 < Value
      attribute :code, Types::Symbol.enum(:existing_target_mismatch)
      attribute :message, Types::String
      attribute :target_event_id, Types::UuidV7
      attribute :existing_event_id, Types::String.constrained(min_size: 1, max_size: 255)
    end
  end
end

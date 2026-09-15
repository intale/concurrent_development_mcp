# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetEventPlanningErrorV1 < Value
      attribute :code, Types::Symbol.enum(
        :duplicate_target_plan,
        :existing_target_plan_mismatch,
        :target_plan_missing,
        :target_plan_changed,
        :target_stream_plan_invalid
      )
      attribute :message, Types::String
      attribute :source_event_id, Types::UuidV7
      attribute :transformation_step, Types::Identifier
      attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 3)
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class PlanHistoryMigrationTargetEvent < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :event_id, Types::UuidV7
      attribute :migration_id, Types::UuidV7
      attribute :plan_id, Types::UuidV7
      attribute :source_event_id, Types::UuidV7
      attribute :source_global_position, Types::GlobalPosition
      attribute :transformation_step, Types::Identifier
      attribute :target_event, EventReference
    end
  end
end

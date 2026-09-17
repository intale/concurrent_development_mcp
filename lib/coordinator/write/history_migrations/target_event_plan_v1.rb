# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetEventPlanV1 < Value
      attribute :source_event_id, Types::UuidV7
      attribute :source_global_position, Types::GlobalPosition
      attribute :transformation_step, Types::Identifier
      attribute :dependency_wave, Types::HistoryMigrationDependencyWave
      attribute :target_event, EventReference
      attribute :planning_event, Types.Instance(PgEventstore::Event)
      attribute :marker, Types::ResourceMarker
      attribute :outcome, Types::String.enum("created", "existing")
    end
  end
end

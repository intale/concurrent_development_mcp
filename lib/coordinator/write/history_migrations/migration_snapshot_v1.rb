# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class MigrationSnapshotV1 < Value
      attribute :migration_id, Types::UuidV7
      attribute :source_config_name, Types::Identifier
      attribute :target_config_name, Types::Identifier
      attribute :source_upper_position, Types::GlobalPosition.optional
      attribute :page_size, Types::HistoryMigrationPageSize
      attribute :next_from_position, Types::GlobalPosition
      attribute :plan_completed, Types::Bool
      attribute :application_dependency_wave, Types::HistoryMigrationDependencyWave
      attribute :application_next_from_position, Types::GlobalPosition
      attribute :completed, Types::Bool
      attribute :abandoned, Types::Bool
      attribute :checkpoint_event, Types.Instance(PgEventstore::Event)
      attribute :latest_revision, Types::StreamRevision
      attribute :source_after_position, Types::GlobalPosition.optional.default(nil)
      attribute :source_command_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 100).default([].freeze)

      def source_from_position
        source_after_position ? source_after_position + 1 : 0
      end

      def plan_completed?
        plan_completed
      end

      def completed?
        completed
      end

      def abandoned?
        abandoned
      end
    end
  end
end

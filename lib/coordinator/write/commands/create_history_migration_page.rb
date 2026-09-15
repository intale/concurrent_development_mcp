# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CreateHistoryMigrationPage < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :migration_id, Types::UuidV7
      attribute :page_id, Types::UuidV7
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :source_event_count, Types::HistoryMigrationSourceEventCount
    end
  end
end

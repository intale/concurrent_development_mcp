# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AdvanceHistoryMigrationApplication < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :migration_id, Types::UuidV7
      attribute :page_id, Types::UuidV7
      attribute :next_from_position, Types::GlobalPosition
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class CompleteHistoryMigration < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :migration_id, Types::UuidV7
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class AbandonHistoryMigration < Value
      attribute :command_id, Types::Identifier
      attribute :actor, Actor
      attribute :migration_id, Types::UuidV7
      attribute :reason, Types::String.constrained(min_size: 1, max_size: 2_000)
    end
  end
end

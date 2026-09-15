# frozen_string_literal: true

module Coordinator::Write
  module Commands
    class ApplyHistoryMigrationPage < Value
      attribute :command_id, Types::UuidV7
      attribute :actor, Actor
      attribute :page_id, Types::UuidV7
      attribute :target_event_count, Types::HistoryMigrationTargetEventCount
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageAppliedV1 < Base
      contract type: "HistoryMigrationPageApplied", version: 1

      attribute :page_id, Types::UuidV7
    end
  end
end

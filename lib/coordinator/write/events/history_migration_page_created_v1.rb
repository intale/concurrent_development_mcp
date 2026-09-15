# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageCreatedV1 < Base
      contract type: "HistoryMigrationPageCreated", version: 1

      attribute :page_id, Types::UuidV7
    end
  end
end

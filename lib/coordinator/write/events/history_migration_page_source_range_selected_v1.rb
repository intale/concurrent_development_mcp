# frozen_string_literal: true

module Coordinator::Write
  module Events
    class HistoryMigrationPageSourceRangeSelectedV1 < Base
      contract type: "HistoryMigrationPageSourceRangeSelected", version: 1

      attribute :page_id, Types::UuidV7
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
    end
  end
end

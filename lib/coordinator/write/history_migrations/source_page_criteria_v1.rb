# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourcePageCriteriaV1 < Value
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::HistoryMigrationPageSize
    end
  end
end

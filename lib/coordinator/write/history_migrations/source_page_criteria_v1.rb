# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourcePageCriteriaV1 < Value
      attribute :from_position, Types::GlobalPosition
      attribute :to_position, Types::GlobalPosition
      attribute :page_size, Types::HistoryMigrationPageSize
      attribute :source_command_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 100).default([].freeze)
    end
  end
end

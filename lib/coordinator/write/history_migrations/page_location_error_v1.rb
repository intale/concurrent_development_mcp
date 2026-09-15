# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageLocationErrorV1 < Value
      attribute :code, Types::Symbol.enum(:page_not_found, :duplicate_page, :invalid_page)
      attribute :message, Types::String
      attribute :migration_id, Types::UuidV7
      attribute :from_position, Types::GlobalPosition
      attribute :event_ids, Types::Array.of(Types::UuidV7).constrained(max_size: 3)
    end
  end
end

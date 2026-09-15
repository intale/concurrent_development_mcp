# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class PageLocationV1 < Value
      attribute :page_id, Types::UuidV7
      attribute :event, Types.Instance(PgEventstore::Event)
      attribute :marker, Types::ResourceMarker
    end
  end
end

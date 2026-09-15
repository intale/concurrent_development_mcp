# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceReader
      def initialize(client:)
        @client = client
      end

      def head_position
        @client.read(
          PgEventstore::Stream.all_stream,
          options: { direction: :desc, max_count: 1 }
        ).first&.global_position
      end

      def page(criteria)
        return [] if criteria.from_position > criteria.to_position

        @client.read(
          PgEventstore::Stream.all_stream,
          options: {
            direction: :asc,
            from_position: criteria.from_position,
            to_position: criteria.to_position,
            max_count: criteria.page_size
          }
        )
      end
    end
  end
end

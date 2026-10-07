# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class SourceReader
      # A fixed domain-contract allowlist, never a list discovered from database contents.
      EVENT_TYPES = (LegacyContractCatalog::SOURCE_CONTRACTS +
        PostRemodelContractCatalog::SOURCE_CONTRACTS).map(&:first).uniq.freeze

      def initialize(client:)
        @client = client
      end

      def head_position(to_position: nil)
        options = { direction: :desc, max_count: 1, filter: { event_types: EVENT_TYPES } }
        options[:from_position] = to_position unless to_position.nil?
        @client.read(
          PgEventstore::Stream.all_stream,
          options:
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
            max_count: criteria.page_size,
            filter: { event_types: EVENT_TYPES }
          }
        )
      end
    end
  end
end

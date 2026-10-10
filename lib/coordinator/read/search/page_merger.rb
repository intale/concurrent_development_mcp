# frozen_string_literal: true

module Coordinator::Read::Search
  class PageMerger
    def initialize(cursor_codec:)
      @cursor_codec = cursor_codec
    end

    def call(rows, query:)
      # SQL has already deduplicated, ordered and capped the final union.
      candidates = rows.first(query.limit + 1)
      has_more = candidates.length > query.limit
      items = candidates.first(query.limit).map do |row|
        attributes = row.fetch("document").transform_keys(&:to_sym)
        evidence = row.fetch("matches").map { Evidence.new(_1.transform_keys(&:to_sym)) }
        Document.new(**attributes, matches: evidence)
      end
      cursor = if has_more
        last = items.last
        @cursor_codec.encode(boundary: CursorBoundary.new(updated_at: last.updated_at, entity_type: last.entity_type, document_id: last.document_id),
          fingerprint: query.fingerprint)
      end
      Page.new(items:, has_more:, cursor:)
    end
  end
end

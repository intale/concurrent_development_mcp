# frozen_string_literal: true

module Coordinator::Read::Web::Repositories
  module EventTimePagination
    private

    def event_time_page(
      relation:,
      id_column:,
      after_updated_at:,
      after_id:,
      limit:,
      sort: "newest_first",
      timestamp_column: :updated_at
    )
      direction = sort == "oldest_first" ? :asc : :desc
      comparator = direction == :asc ? ">" : "<"
      if after_updated_at && after_id
        relation = relation.where(
          "#{timestamp_column} #{comparator} :updated_at OR " \
          "(#{timestamp_column} = :updated_at AND #{id_column} #{comparator} :id)",
          updated_at: after_updated_at,
          id: after_id
        )
      end
      rows = relation.order(timestamp_column => direction, id_column => direction).limit(limit + 1).to_a
      [ rows.first(limit), rows.length > limit ]
    end

    def event_time(record)
      record.updated_at.utc.iso8601(6)
    end
  end
end

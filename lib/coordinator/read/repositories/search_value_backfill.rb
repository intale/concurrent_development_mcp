# frozen_string_literal: true

module Coordinator::Read::Repositories
  # Disposable nested text only. Source row locks serialize each bounded batch
  # with the same-source trigger updates; no source/event history is replayed.
  class SearchValueBackfill
    SOURCES = {
      "development_artifacts" => "artifact_id",
      "development_artifact_observations" => "observation_id",
      "agent_choices" => "choice_id",
      "decision_definitions" => "decision_id",
      "coordinator_contexts" => "change_set_id"
    }.freeze
    BATCH_SIZE = 100

    def call
      ApplicationRecord.connection_pool.with_connection do |connection|
        SOURCES.sum { |table, key| backfill_source(connection, table, key) }
      end
    end

    private

    def backfill_source(connection, table, key)
      after = nil
      count = 0
      loop do
        ids = connection.transaction do
          condition = after ? "WHERE #{key} > #{connection.quote(after)}" : ""
          locked_ids = connection.select_values(
            "SELECT #{key} FROM #{table} #{condition} ORDER BY #{key} LIMIT #{BATCH_SIZE} FOR UPDATE"
          )
          unless locked_ids.empty?
            connection.execute(<<~SQL)
              SELECT coordinator_sync_search_values('#{table}', #{key}, to_jsonb(source))
              FROM #{table} AS source
              WHERE #{key} IN (#{locked_ids.map { connection.quote(_1) }.join(',')})
              ORDER BY #{key}
            SQL
          end
          locked_ids
        end
        break if ids.empty?

        count += ids.length
        after = ids.last
      end
      count
    end
  end
end

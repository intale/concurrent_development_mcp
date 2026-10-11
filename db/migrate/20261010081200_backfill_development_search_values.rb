# frozen_string_literal: true

class BackfillDevelopmentSearchValues < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!
  SOURCES = {
    "development_artifacts" => "artifact_id",
    "development_artifact_observations" => "observation_id",
    "agent_choices" => "choice_id",
    "decision_definitions" => "decision_id",
    "coordinator_contexts" => "change_set_id"
  }.freeze

  def up
    # Keep this historical migration independent of today's application code:
    # later migrations may change the functions used by the runtime backfill.
    # Each batch commits independently with the then-installed SQL contract.
    SOURCES.each do |table, key|
      after = nil
      loop do
        ids = connection.transaction do
          condition = after ? "WHERE #{key} > #{connection.quote(after)}" : ""
          selected = connection.select_values("SELECT #{key} FROM #{table} #{condition} ORDER BY #{key} LIMIT 100 FOR UPDATE")
          unless selected.empty?
            connection.execute(<<~SQL)
              SELECT coordinator_sync_search_values('#{table}', #{key}, to_jsonb(source))
              FROM #{table} AS source
              WHERE #{key} IN (#{selected.map { connection.quote(_1) }.join(',')})
              ORDER BY #{key}
            SQL
          end
          selected
        end
        break if ids.empty?

        after = ids.last
      end
    end
  end

  def down
    # Derived data remains valid for the already-installed schema and triggers.
  end
end

# frozen_string_literal: true

module ProjectionBatchMeasurement
  module_function

  # SQL timings are scoped to this callback. WAL is a cluster-wide upper bound
  # if other workers write concurrently; neither measurement resets statistics.
  def call(model)
    model.connection_pool.with_connection do |connection|
      before_lsn = connection.select_value("SELECT pg_current_wal_insert_lsn()")
      allocations = GC.stat(:total_allocated_objects)
      rss = resident_kilobytes
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      statements = []
      capture = lambda do |_name, start, finish, _id, payload|
        next unless payload.fetch(:sql).match?(/\A(?:INSERT|UPDATE|DELETE)\b/i)

        statements << { sql: payload.fetch(:sql), binds: payload.fetch(:binds, []), duration_ms: (finish - start) * 1000 }
      end
      ActiveSupport::Notifications.subscribed(capture, "sql.active_record") { yield }
      wall_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
      allocated_objects = GC.stat(:total_allocated_objects) - allocations
      after_lsn = connection.select_value("SELECT pg_current_wal_insert_lsn()")
      wal_bytes = connection.select_value("SELECT pg_wal_lsn_diff(#{connection.quote(after_lsn)}, #{connection.quote(before_lsn)})").to_i
      { statements:, statement_count: statements.length, sql_duration_ms: statements.sum { _1.fetch(:duration_ms) },
        wall_ms:, allocated_objects:, rss_delta_kb: resident_kilobytes - rss, cluster_wal_upper_bound_bytes: wal_bytes }
    end
  end

  def resident_kilobytes
    return 0 unless File.readable?("/proc/self/status")

    File.foreach("/proc/self/status").find { _1.start_with?("VmRSS:") }.to_s.split[1].to_i
  end

  # Executes the captured statement again, only in isolated test fixtures.
  # EXPLAIN's statement-local WAL avoids attributing unrelated cluster writes.
  def explain(model, statement)
    model.connection_pool.with_connection do |connection|
      result = connection.exec_query("EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON) #{statement.fetch(:sql)}",
        "Projection measurement", statement.fetch(:binds))
      document = JSON.parse(result.rows.sole.sole).sole
      { execution_ms: document.fetch("Execution Time"), planning_ms: document.fetch("Planning Time"),
        wal_bytes: document.fetch("Plan").fetch("WAL Bytes", 0),
        triggers: document.fetch("Triggers", []).map { _1.slice("Trigger Name", "Time", "Calls") } }
    end
  end
end

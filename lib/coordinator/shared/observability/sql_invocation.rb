# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class SqlInvocation
      def initialize(session:)
        @session = session
      end

      def call(sql:, started_at:, finished_at:, exception_type: nil)
        operation = SqlStatement.operation(sql)
        outcome = exception_type ? "error" : "ok"
        labels = { "db.operation.name" => operation, "outcome" => outcome }
        elapsed = [ finished_at - started_at, 0.0 ].max
        Runtime.safely(:sql_completed) { @session.record(:sql_completed, 1, attributes: labels) }
        Runtime.safely(:sql_duration) { @session.record(:sql_duration, elapsed, attributes: labels) }
        Runtime.safely(:sql_span) do
          attributes = labels.merge("db.system.name" => "postgresql")
          text = SqlStatement.text(sql)
          attributes["db.query.text"] = text if text
          attributes["exception.type"] = exception_type if exception_type
          # Rails supplies monotonic execution times. Translate both endpoints
          # together; callback/export time is not treated as query runtime.
          offset = Process.clock_gettime(Process::CLOCK_REALTIME) - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          span = @session.tracer.start_span("SQL #{operation}", kind: :client, attributes:, start_timestamp: started_at + offset)
          span.status = OpenTelemetry::Trace::Status.error if exception_type
          span.finish(end_timestamp: finished_at + offset)
        end
        nil
      end
    end
  end
end

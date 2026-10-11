# frozen_string_literal: true

module ObservabilityTestHelpers
  def start_test_observability(env: {})
    Coordinator::Shared::Observability::Runtime.configure(
      environment: "test", env: env.merge("COORDINATOR_OBSERVABILITY_ENABLED" => "true")
    )
  end

  def telemetry_spans
    Coordinator::Shared::Observability::Runtime.current.span_exporter.finished_spans
  end

  def telemetry_metrics
    session = Coordinator::Shared::Observability::Runtime.current
    session.metric_reader.reset
    session.metric_reader.pull
    session.metric_reader.metric_snapshots
  end
end

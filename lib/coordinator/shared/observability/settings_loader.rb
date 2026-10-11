# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    class SettingsLoader
      def initialize(contract: SettingsContract.new)
        @contract = contract
      end

      def call(environment:, env: ENV.to_h)
        result = @contract.call(
          enabled: env.fetch("COORDINATOR_OBSERVABILITY_ENABLED", "false"),
          mode: environment == "test" ? "in_memory" : "otlp",
          environment:,
          service_name: env.fetch("OTEL_SERVICE_NAME", "concurrent-development-coordinator"),
          service_version: env.fetch("COORDINATOR_SERVICE_VERSION", "development"),
          role: env.fetch("COORDINATOR_OBSERVABILITY_ROLE", "web"),
          traces_endpoint: env.fetch("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "http://localhost:4318/v1/traces"),
          metrics_endpoint: env.fetch("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", "http://localhost:9090/api/v1/otlp/v1/metrics"),
          export_interval_ms: env.fetch("OTEL_METRIC_EXPORT_INTERVAL", "10000"),
          export_timeout_ms: env.fetch("COORDINATOR_OBSERVABILITY_EXPORT_TIMEOUT_MS", "3000"),
          trace_sample_ratio: env.fetch("COORDINATOR_OBSERVABILITY_TRACE_SAMPLE_RATIO", "1.0")
        )
        # Do not include endpoint values or other environment contents in errors.
        raise ArgumentError, "Invalid observability settings: #{result.errors.to_h.keys.join(', ')}" unless result.success?

        Settings.new(result.to_h)
      end
    end
  end
end

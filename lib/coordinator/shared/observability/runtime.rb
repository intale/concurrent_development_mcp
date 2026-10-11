# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    module Runtime
      @mutex = Mutex.new
      @failure_mutex = Mutex.new
      @reported_failures = {}

      class << self
        def configure(environment:, env: ENV.to_h)
          start(SettingsLoader.new.call(environment:, env:))
        rescue StandardError => error
          shutdown
          report(:configuration, error)
          nil
        end

        def start(settings)
          @mutex.synchronize do
            return @session if @session&.settings == settings && @session.pid == Process.pid

            @session&.shutdown
            @session = nil
            @settings = settings
            @session = Session.new(settings:) if settings.enabled
            OpenTelemetry.tracer_provider = @session ? @session.tracer_provider : OpenTelemetry::Trace::TracerProvider.new
            OpenTelemetry.meter_provider = @session ? @session.meter_provider : OpenTelemetry::Metrics::MeterProvider.new
            @session
          end
        rescue StandardError => error
          @session = nil
          reset_providers
          report(:startup, error)
          nil
        end

        def current
          @session
        end

        # Queue children inherit providers but not the exporting threads.
        # Threaded workers keep sharing the current process's providers.
        def ensure_process
          after_fork if @session && @session.pid != Process.pid
          nil
        end

        def shutdown
          @mutex.synchronize do
            session = @session
            @session = nil
            safely(:shutdown) { session&.shutdown }
            OpenTelemetry.tracer_provider = OpenTelemetry::Trace::TracerProvider.new
            OpenTelemetry.meter_provider = OpenTelemetry::Metrics::MeterProvider.new
          end
          nil
        end

        def after_fork
          @mutex = Mutex.new
          @failure_mutex = Mutex.new
          @reported_failures = {}
          @session&.detach_observers
          @session = nil
          start(@settings) if @settings
          nil
        end

        # This guard is only for telemetry operations, never the business block.
        def safely(operation)
          yield
        rescue StandardError => error
          report(operation, error)
          nil
        end

        private

        def report(operation, error)
          first = @failure_mutex.synchronize do
            next false if @reported_failures.key?(operation)

            @reported_failures[operation] = true
          end
          warn("Coordinator telemetry #{operation} unavailable (#{error.class.name})") if first
          nil
        end

        def reset_providers
          OpenTelemetry.tracer_provider = OpenTelemetry::Trace::TracerProvider.new
          OpenTelemetry.meter_provider = OpenTelemetry::Metrics::MeterProvider.new
          nil
        end
      end
    end
  end
end

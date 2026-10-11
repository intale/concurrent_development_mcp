# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    # Owns one process's SDK providers. It never starts network readers in test.
    class Session
      SCOPE = "coordinator".freeze
      CARDINALITY_LIMIT = 10000

      attr_reader :settings, :pid, :instance_id, :tracer_provider, :meter_provider,
                  :span_exporter, :metric_reader, :tracer

      def initialize(settings:, instance_id: SecureRandom.uuid_v7)
        @settings = settings
        @pid = Process.pid
        @instance_id = instance_id
        @observer_mutex = Mutex.new
        @observers = {}
        @definitions = Contract.metrics.to_h { [ _1.key, _1 ] }
        resource = OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
        build_tracing(resource)
        build_metrics(resource)
      rescue StandardError
        shutdown
        raise
      end

      def record(key, value, attributes:)
        definition = @definitions.fetch(key)
        instrument = @instruments.fetch(key)
        labels = attributes.slice(*definition.dimensions)
        if definition.kind == :histogram
          instrument.record(value, attributes: labels)
        else
          instrument.add(value, attributes: labels)
        end
        nil
      end

      # The current Ruby SDK observable API returns a scalar per callback.
      # A bounded scope per label tuple gives each callback its own fixed labels.
      def register_observer(key, attributes:, &callback)
        definition = @definitions.fetch(key)
        labels = attributes.slice(*definition.dimensions).freeze
        @observer_mutex.synchronize do
          @observers[[ key, labels ]] ||= begin
            meter = meter_provider.meter("#{SCOPE}.observable", attributes: labels)
            gauge = meter.create_observable_gauge(definition.name, unit: definition.unit, description: definition.description)
            gauge.add_attributes(labels.dup)
            gauge.timeout(1)
            gauge.register_callback(callback)
            gauge
          end
        end
        nil
      end

      def force_flush
        tracer_provider.force_flush(timeout: timeout)
        memory? ? metric_reader.pull : meter_provider.force_flush(timeout: timeout)
        nil
      end

      def shutdown
        return if @stopped

        @stopped = true
        begin
          tracer_provider&.shutdown(timeout: timeout)
        ensure
          # The SDK's in-memory reader has a no-argument, no-op shutdown.
          # It owns no thread; avoid MeterProvider's keyword forwarding to it.
          memory? ? metric_reader&.shutdown : meter_provider&.shutdown(timeout: timeout)
        end
        nil
      end

      private

      def memory?
        settings.environment == "test" || settings.mode == "in_memory"
      end

      def timeout
        settings.export_timeout_ms / 1000.0
      end

      def resource_attributes
        {
          "service.name" => settings.service_name,
          "service.version" => settings.service_version,
          "service.instance.id" => instance_id,
          "deployment.environment.name" => settings.environment,
          "coordinator.process.role" => settings.role
        }
      end

      def build_tracing(resource)
        @tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new(
          resource:,
          sampler: OpenTelemetry::SDK::Trace::Samplers.parent_based(
            root: OpenTelemetry::SDK::Trace::Samplers.trace_id_ratio_based(settings.trace_sample_ratio)
          ),
          span_limits: OpenTelemetry::SDK::Trace::SpanLimits.new(attribute_count_limit: 32, attribute_length_limit: 512)
        )
        @span_exporter = if memory?
                           OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
        else
                           OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: settings.traces_endpoint, timeout:)
        end
        processor = if memory?
                      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(span_exporter)
        else
                      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
                        span_exporter, exporter_timeout: settings.export_timeout_ms,
                        schedule_delay: 1000, max_queue_size: 2048, max_export_batch_size: 256
                      )
        end
        tracer_provider.add_span_processor(processor)
        @tracer = tracer_provider.tracer(SCOPE)
      end

      def build_metrics(resource)
        @meter_provider = OpenTelemetry::SDK::Metrics::MeterProvider.new(resource:)
        @metric_reader = if memory?
                           OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter.new(aggregation_cardinality_limit: CARDINALITY_LIMIT)
        else
                           OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
                             exporter: OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(endpoint: settings.metrics_endpoint, timeout:),
                             export_interval_millis: settings.export_interval_ms,
                             export_timeout_millis: settings.export_timeout_ms,
                             aggregation_cardinality_limit: CARDINALITY_LIMIT
                           )
        end
        meter_provider.add_metric_reader(metric_reader)
        @definitions.each_value do |definition|
          meter_provider.add_view(definition.name, aggregation: aggregation(definition), aggregation_cardinality_limit: CARDINALITY_LIMIT)
        end
        meter = meter_provider.meter(SCOPE)
        @instruments = @definitions.values.reject { _1.kind == :observable_gauge }.to_h do |definition|
          instrument = meter.public_send("create_#{definition.kind}", definition.name, unit: definition.unit, description: definition.description)
          [ definition.key, instrument ]
        end
      end

      def aggregation(definition)
        case definition.kind
        when :histogram
          OpenTelemetry::SDK::Metrics::Aggregation::ExplicitBucketHistogram.new(
            boundaries: definition.boundaries, aggregation_temporality: :cumulative
          )
        when :observable_gauge
          OpenTelemetry::SDK::Metrics::Aggregation::LastValue.new
        else
          OpenTelemetry::SDK::Metrics::Aggregation::Sum.new(
            monotonic: definition.kind == :counter, aggregation_temporality: :cumulative
          )
        end
      end
    end
  end
end

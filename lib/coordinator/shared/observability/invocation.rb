# frozen_string_literal: true

module Coordinator::Shared
  module Observability
    # Only telemetry operations are guarded. The caller's block runs once,
    # outside every fail-open guard, with its result/exception unchanged.
    class Invocation
      def initialize(session:, prefix:, name:, attributes:)
        @session = session
        @prefix = prefix
        @name = name
        @attributes = attributes
      end

      def call(outcome:)
        completed = false
        start
        result = yield
        completed = true
        result
      ensure
        error = $! unless completed
        value = if error
                  "error"
        elsif completed
                  Runtime.safely(:invocation_outcome) { outcome.call(result) } || "unknown"
        else
                  "unknown"
        end
        finish(outcome: Contract.outcome(value), exception_type: error&.class&.name)
      end

      private

      def start
        @started_at = Runtime.safely(:invocation_clock) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @span = Runtime.safely(:span_start) { @session.tracer.start_span(@name, attributes: @attributes.dup) }
        @context_token = Runtime.safely(:span_context) do
          OpenTelemetry::Context.attach(OpenTelemetry::Trace.context_with_span(@span)) if @span
        end
        Runtime.safely(:invocation_started) { @session.record(:"#{@prefix}_started", 1, attributes: @attributes) }
        @in_flight_recorded = Runtime.safely(:invocation_in_flight) do
          @session.record(:"#{@prefix}_in_flight", 1, attributes: @attributes)
          true
        end
        nil
      end

      def finish(outcome:, exception_type:)
        labels = @attributes.merge("outcome" => outcome)
        Runtime.safely(:invocation_completed) { @session.record(:"#{@prefix}_completed", 1, attributes: labels) }
        Runtime.safely(:invocation_duration) do
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
          @session.record(:"#{@prefix}_duration", elapsed, attributes: labels)
        end
        Runtime.safely(:invocation_in_flight) do
          @session.record(:"#{@prefix}_in_flight", -1, attributes: @attributes) if @in_flight_recorded
        end
        Runtime.safely(:span_context) { OpenTelemetry::Context.detach(@context_token) if @context_token }
        Runtime.safely(:span_finish) do
          if @span
            @span.set_attribute("outcome", outcome)
            @span.set_attribute("exception.type", exception_type) if exception_type
            @span.status = OpenTelemetry::Trace::Status.error if !%w[ok accepted pending not_modified].include?(outcome)
            @span.finish
          end
        end
        nil
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class RegistrySweepLoader
      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(scan_id)
        stream = @stream_factory.candidate_impact_registry_sweep(scan_id)
        events = @event_store.read_grouped(stream, EventQueries::CANDIDATE_IMPACT_REGISTRY_SWEEP_STATE)
        source_events = @event_store.read(stream, EventQueries::CANDIDATE_IMPACT_REGISTRY_SWEEP_SOURCES)
        payloads = events.map { load(_1) }
        sources = source_events.to_h { |event| [ load(event).role, load(event).source ] }

        RegistrySweepSnapshot.new(
          state: build_state(events, payloads, sources),
          latest_revision: (events + source_events).map(&:stream_revision).max,
          persisted_events: events
        )
      end

      private

      def build_state(events, payloads, sources)
        return Domain::CandidateObligationScans::RegistrySweepState.initial if events.empty?

        validate_sources!(sources)
        skipped = payloads.find { _1.is_a?(Events::CandidateImpactRegistrySweepSkippedV2) }
        return skipped_state(skipped, events.fetch(payloads.index(skipped)), sources) if skipped

        started = payloads.find { _1.is_a?(Events::CandidateImpactRegistrySweepStartedV2) }
        invalid!("started_event_missing") unless started
        started_event = events.fetch(payloads.index(started))
        progressed = payloads.find { _1.is_a?(Events::CandidateImpactRegistrySweepProgressedV2) }
        completed = payloads.find { _1.is_a?(Events::CandidateImpactRegistrySweepCompletedV2) }
        return completed_state(started, started_event, progressed, completed, events.fetch(payloads.index(completed)), sources) if completed

        running_state(started, started_event, progressed, progressed && events.fetch(payloads.index(progressed)), sources)
      end

      def skipped_state(payload, event, sources)
        Domain::CandidateObligationScans::RegistrySweepState.new(
          status: "skipped",
          scan_id: payload.scan_id,
          change_set_id: nil,
          policy_partition_event: sources["policy_partition"],
          policy_head: head(sources["policy_head"]),
          started_event: nil,
          checkpoint_event: reference(event),
          from_revision: nil,
          to_revision: nil,
          page_size: nil,
          page_count: 0,
          rule_version: event.metadata.fetch("policy_version"),
          skip_reason: payload.reason
        )
      end

      def completed_state(started, started_event, progressed, _completed, completed_event, sources)
        state(
          status: "completed",
          started:,
          started_event:,
          checkpoint_event: completed_event,
          from_revision: nil,
          page_count: (progressed&.page_number || 0) + 1,
          sources:
        )
      end

      def running_state(started, started_event, progressed, progressed_event, sources)
        state(
          status: "running",
          started:,
          started_event:,
          checkpoint_event: progressed_event || started_event,
          from_revision: progressed ? progressed.next_from_revision : started.from_revision,
          page_count: progressed ? progressed.page_number : 0,
          sources:
        )
      end

      def state(status:, started:, started_event:, checkpoint_event:, from_revision:, page_count:, sources:)
        Domain::CandidateObligationScans::RegistrySweepState.new(
          status:,
          scan_id: started.scan_id,
          change_set_id: started.change_set_id,
          policy_partition_event: sources.fetch("policy_partition"),
          policy_head: head(sources.fetch("policy_head")),
          started_event: reference(started_event),
          checkpoint_event: reference(checkpoint_event),
          from_revision:,
          to_revision: started.to_revision,
          page_size: started.page_size,
          page_count:,
          rule_version: started_event.metadata.fetch("policy_version"),
          skip_reason: nil
        )
      end

      def validate_sources!(sources)
        invalid!("scan_sources_invalid") unless sources.keys.sort == %w[policy_head policy_partition]
      end

      def head(source)
        return unless source

        Decisions::DecisionHeadV1.new(
          decision_id: source.stream_id,
          decision_revision: source.stream_revision,
          event: source
        )
      end

      def load(event)
        @schema_registry.load(type: event.type, schema_version: event.metadata.fetch("schema_version"), data: event.data)
      end

      def reference(event)
        EventReference.new(
          event_id: event.id,
          type: event.type,
          stream_context: event.stream.context,
          stream_name: event.stream.stream_name,
          stream_id: event.stream.stream_id,
          stream_revision: event.stream_revision
        )
      end

      def invalid!(reason)
        raise CandidateObligations::InvalidHistory.new(reason:, evidence: {})
      end
    end
  end
end

# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class PairScanLoader
      SOURCE_ROLES = %w[policy_head policy_partition source_registration].freeze

      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(scan_id)
        stream = @stream_factory.candidate_impact_pair_scan(scan_id)
        events = @event_store.read_grouped(stream, EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_STATE)
        source_events = @event_store.read(stream, EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_SOURCES)
        payloads = events.map { load(_1) }
        sources = source_events.to_h { |event| [ load(event).role, load(event).source ] }

        PairScanSnapshot.new(
          state: build_state(events, payloads, sources),
          latest_revision: (events + source_events).map(&:stream_revision).max,
          persisted_events: events
        )
      end

      private

      def build_state(events, payloads, sources)
        return Domain::CandidateObligationScans::PairScanState.initial if events.empty?

        validate_sources!(sources)
        skipped = payloads.find { _1.is_a?(Events::CandidateImpactPairScanSkippedV2) }
        return skipped_state(skipped, events.fetch(payloads.index(skipped)), sources) if skipped

        started = payloads.find { _1.is_a?(Events::CandidateImpactPairScanStartedV2) }
        invalid!("started_event_missing") unless started
        started_event = events.fetch(payloads.index(started))
        progressed = payloads.find { _1.is_a?(Events::CandidateImpactPairScanProgressedV2) }
        completed = payloads.find { _1.is_a?(Events::CandidateImpactPairScanCompletedV2) }
        return completed_state(started, started_event, progressed, completed, events.fetch(payloads.index(completed)), sources) if completed

        running_state(started, started_event, progressed, progressed && events.fetch(payloads.index(progressed)), sources)
      end

      def skipped_state(payload, event, sources)
        Domain::CandidateObligationScans::PairScanState.new(
          **source_values(sources),
          status: "skipped",
          scan_id: payload.scan_id,
          change_set_id: nil,
          direction: nil,
          markers: [],
          started_event: nil,
          checkpoint_event: reference(event),
          from_revision: nil,
          to_revision: nil,
          page_size: nil,
          page_count: 0,
          index_policy_version: event.metadata.fetch("index_policy_version"),
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
        Domain::CandidateObligationScans::PairScanState.new(
          **source_values(sources),
          status:,
          scan_id: started.scan_id,
          change_set_id: started.change_set_id,
          direction: started.direction,
          markers: started.markers,
          started_event: reference(started_event),
          checkpoint_event: reference(checkpoint_event),
          from_revision:,
          to_revision: started.to_revision,
          page_size: started.page_size,
          page_count:,
          index_policy_version: started_event.metadata.fetch("index_policy_version"),
          rule_version: started_event.metadata.fetch("policy_version"),
          skip_reason: nil
        )
      end

      def source_values(sources)
        {
          source_registration: sources.fetch("source_registration"),
          policy_partition_event: sources.fetch("policy_partition"),
          policy_head: head(sources.fetch("policy_head"))
        }
      end

      def validate_sources!(sources)
        invalid!("scan_sources_invalid") unless sources.keys.sort == SOURCE_ROLES
      end

      def head(source)
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

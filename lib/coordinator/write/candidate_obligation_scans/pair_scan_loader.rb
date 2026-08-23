# frozen_string_literal: true

module Coordinator::Write
  module CandidateObligationScans
    class PairScanLoader
      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(scan_id)
        events = @event_store.read_grouped(
          @stream_factory.candidate_impact_pair_scan(scan_id),
          EventQueries::CANDIDATE_IMPACT_PAIR_SCAN_STATE
        )
        payloads = events.map { load(_1) }

        PairScanSnapshot.new(
          state: build_state(events, payloads),
          latest_revision: events.first&.stream_revision,
          persisted_events: events
        )
      end

      private

      def build_state(events, payloads)
        return Domain::CandidateObligationScans::PairScanState.initial if events.empty?

        skipped = payloads.find { _1.is_a?(Events::CandidateImpactPairScanSkippedV1) }
        return skipped_state(skipped, events.fetch(payloads.index(skipped))) if skipped

        started = payloads.find { _1.is_a?(Events::CandidateImpactPairScanStartedV1) }
        started_event = events.fetch(payloads.index(started))
        completed = payloads.find { _1.is_a?(Events::CandidateImpactPairScanCompletedV1) }
        return completed_state(started, started_event, completed, events.fetch(payloads.index(completed))) if completed

        progressed = payloads.find { _1.is_a?(Events::CandidateImpactPairScanProgressedV1) }
        running_state(started, started_event, progressed, progressed && events.fetch(payloads.index(progressed)))
      end

      def skipped_state(payload, event)
        Domain::CandidateObligationScans::PairScanState.new(
          **common(payload),
          status: "skipped",
          markers: payload.markers,
          started_event: nil,
          checkpoint_event: reference(event),
          from_revision: nil,
          to_revision: payload.to_revision,
          page_count: 0,
          total_registration_count: 0,
          skip_reason: payload.reason
        )
      end

      def completed_state(started, started_event, completed, completed_event)
        state(
          status: "completed",
          started:,
          started_event:,
          checkpoint_event: completed_event,
          from_revision: completed.final_from_revision,
          page_count: completed.page_count,
          total_registration_count: completed.total_registration_count
        )
      end

      def running_state(started, started_event, progressed, progressed_event)
        state(
          status: "running",
          started:,
          started_event:,
          checkpoint_event: progressed_event || started_event,
          from_revision: progressed ? progressed.next_from_revision : started.from_revision,
          page_count: progressed ? progressed.page_number : 0,
          total_registration_count: progressed ? progressed.total_registration_count : 0
        )
      end

      def state(status:, started:, started_event:, checkpoint_event:, from_revision:, page_count:, total_registration_count:)
        Domain::CandidateObligationScans::PairScanState.new(
          **common(started),
          status:,
          markers: started.markers,
          started_event: reference(started_event),
          checkpoint_event: reference(checkpoint_event),
          from_revision:,
          to_revision: started.to_revision,
          page_count:,
          total_registration_count:,
          skip_reason: nil
        )
      end

      def common(payload)
        {
          scan_id: payload.scan_id,
          change_set_id: payload.change_set_id,
          source_registration: payload.source_registration,
          direction: payload.direction,
          policy_partition_event: payload.policy_partition_event,
          policy_head: payload.policy_head,
          page_size: payload.page_size,
          index_policy_version: payload.index_policy_version,
          rule_version: payload.rule_version
        }
      end

      def load(event)
        @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
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
    end
  end
end

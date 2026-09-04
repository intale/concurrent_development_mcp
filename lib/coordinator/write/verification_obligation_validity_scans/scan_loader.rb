# frozen_string_literal: true

module Coordinator::Write
  module VerificationObligationValidityScans
    class ScanLoader
      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(scan_id)
        stream = @stream_factory.verification_obligation_validity_scan(scan_id)
        events = @event_store.read_grouped(stream, EventQueries::VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATE)
        source_events = @event_store.read(stream, EventQueries::VERIFICATION_OBLIGATION_VALIDITY_SCAN_SOURCES)
        payloads = events.map { load(_1) }
        sources = source_events.to_h { |event| [ load(event).role, load(event).source ] }
        ScanSnapshot.new(
          state: build_state(events, payloads, sources),
          latest_revision: (events + source_events).map(&:stream_revision).max,
          persisted_events: events
        )
      end

      private

      def build_state(events, payloads, sources)
        return Domain::VerificationObligationValidityScans::State.initial if events.empty?

        source = sources["superseding_partition"]
        invalid!("scan_source_invalid") unless sources.length == 1 && source
        started = payloads.find { _1.is_a?(Events::VerificationObligationValidityScanStartedV2) }
        invalid!("started_event_missing") unless started
        started_event = events.fetch(payloads.index(started))
        progressed = payloads.find { _1.is_a?(Events::VerificationObligationValidityScanProgressedV2) }
        completed = payloads.find { _1.is_a?(Events::VerificationObligationValidityScanCompletedV2) }
        return completed_state(started, started_event, progressed, completed, events.fetch(payloads.index(completed)), source) if completed

        running_state(started, started_event, progressed, progressed && events.fetch(payloads.index(progressed)), source)
      end

      def completed_state(started, started_event, progressed, _completed, completed_event, source)
        state(
          status: "completed",
          started:,
          started_event:,
          checkpoint_event: completed_event,
          from_position: nil,
          page_count: (progressed&.page_number || 0) + 1,
          source:
        )
      end

      def running_state(started, started_event, progressed, progressed_event, source)
        state(
          status: "running",
          started:,
          started_event:,
          checkpoint_event: progressed_event || started_event,
          from_position: progressed ? progressed.next_from_position : started.from_position,
          page_count: progressed ? progressed.page_number : 0,
          source:
        )
      end

      def state(status:, started:, started_event:, checkpoint_event:, from_position:, page_count:, source:)
        Domain::VerificationObligationValidityScans::State.new(
          status:,
          scan_id: started.scan_id,
          change_set_id: started.change_set_id,
          superseding_partition_event: source,
          started_event: reference(started_event),
          checkpoint_event: reference(checkpoint_event),
          from_position:,
          to_position: started.to_position,
          page_size: started.page_size,
          page_count:,
          rule_version: started_event.metadata.fetch("policy_version")
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

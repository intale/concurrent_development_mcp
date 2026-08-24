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
        events = @event_store.read_grouped(
          @stream_factory.verification_obligation_validity_scan(scan_id),
          EventQueries::VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATE
        )
        payloads = events.map { load(_1) }
        ScanSnapshot.new(
          state: build_state(events, payloads),
          latest_revision: events.first&.stream_revision,
          persisted_events: events
        )
      end

      private

      def build_state(events, payloads)
        return Domain::VerificationObligationValidityScans::State.initial if events.empty?

        started = payloads.find { _1.is_a?(Events::VerificationObligationValidityScanStartedV1) }
        started_event = events.fetch(payloads.index(started))
        completed = payloads.find { _1.is_a?(Events::VerificationObligationValidityScanCompletedV1) }
        return completed_state(started, started_event, completed, events.fetch(payloads.index(completed))) if completed

        progressed = payloads.find { _1.is_a?(Events::VerificationObligationValidityScanProgressedV1) }
        running_state(started, started_event, progressed, progressed && events.fetch(payloads.index(progressed)))
      end

      def completed_state(started, started_event, completed, completed_event)
        state(
          status: "completed",
          started:,
          started_event:,
          checkpoint_event: completed_event,
          from_position: completed.final_from_position,
          page_count: completed.page_count,
          total_obligation_count: completed.total_obligation_count
        )
      end

      def running_state(started, started_event, progressed, progressed_event)
        state(
          status: "running",
          started:,
          started_event:,
          checkpoint_event: progressed_event || started_event,
          from_position: progressed ? progressed.next_from_position : started.from_position,
          page_count: progressed ? progressed.page_number : 0,
          total_obligation_count: progressed ? progressed.total_obligation_count : 0
        )
      end

      def state(status:, started:, started_event:, checkpoint_event:, from_position:, page_count:, total_obligation_count:)
        Domain::VerificationObligationValidityScans::State.new(
          status:,
          scan_id: started.scan_id,
          change_set_id: started.change_set_id,
          superseding_partition_event: started.superseding_partition_event,
          started_event: reference(started_event),
          checkpoint_event: reference(checkpoint_event),
          from_position:,
          to_position: started.to_position,
          page_size: started.page_size,
          page_count:,
          total_obligation_count:,
          rule_version: started.rule_version
        )
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

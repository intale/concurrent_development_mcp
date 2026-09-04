# frozen_string_literal: true

module Coordinator::Write
  module AgentChoiceImpacts
    class ScanLoader
      def initialize(event_store:, stream_factory: StreamFactory.new, schema_registry: EventSchemaRegistry.new)
        @event_store = event_store
        @stream_factory = stream_factory
        @schema_registry = schema_registry
      end

      def call(scan_id)
        stream = @stream_factory.agent_choice_impact_scan(scan_id)
        events = @event_store.read_grouped(stream, EventQueries::AGENT_CHOICE_IMPACT_SCAN_STATE)
        source_events = @event_store.read(stream, EventQueries::AGENT_CHOICE_IMPACT_SCAN_SOURCES)
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
        return Domain::AgentChoiceImpacts::ScanState.initial if events.empty?

        skipped = payloads.find { _1.is_a?(Events::AgentChoiceImpactScanSkippedV2) }
        return skipped_state(skipped, events.fetch(payloads.index(skipped))) if skipped

        started = payloads.find { _1.is_a?(Events::AgentChoiceImpactScanStartedV2) }
        invalid!("started_event_missing") unless started
        invalid!("decision_change_source_missing") unless sources["decision_change"] == started.decision_change.source_event
        started_event = events.fetch(payloads.index(started))
        progressed = payloads.find { _1.is_a?(Events::AgentChoiceImpactScanProgressedV2) }
        completed = payloads.find { _1.is_a?(Events::AgentChoiceImpactScanCompletedV2) }
        return completed_state(started, started_event, progressed, completed, events.fetch(payloads.index(completed))) if completed

        running_state(started, started_event, progressed, progressed && events.fetch(payloads.index(progressed)))
      end

      def skipped_state(payload, event)
        Domain::AgentChoiceImpacts::ScanState.new(
          status: "skipped",
          scan_id: payload.scan_id,
          decision_change: nil,
          started_event: nil,
          checkpoint_event: reference(event),
          from_position: nil,
          to_position: nil,
          page_size: nil,
          page_count: 0,
          policy_version: event.metadata.fetch("policy_version"),
          skip_reason: payload.reason
        )
      end

      def completed_state(started, started_event, progressed, _completed, completed_event)
        Domain::AgentChoiceImpacts::ScanState.new(
          **common(started, started_event),
          status: "completed",
          checkpoint_event: reference(completed_event),
          from_position: nil,
          page_count: (progressed&.page_number || 0) + 1
        )
      end

      def running_state(started, started_event, progressed, progressed_event)
        Domain::AgentChoiceImpacts::ScanState.new(
          **common(started, started_event),
          status: "running",
          checkpoint_event: reference(progressed_event || started_event),
          from_position: progressed ? progressed.next_from_position : started.from_position,
          page_count: progressed ? progressed.page_number : 0
        )
      end

      def common(started, started_event)
        {
          scan_id: started.scan_id,
          decision_change: started.decision_change,
          started_event: reference(started_event),
          to_position: started.to_position,
          page_size: started.page_size,
          policy_version: started_event.metadata.fetch("policy_version"),
          skip_reason: nil
        }
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
        raise InvalidHistory.new(reason:, evidence: {})
      end
    end
  end
end

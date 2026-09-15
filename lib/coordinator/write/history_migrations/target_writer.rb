# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class TargetWriter
      include Dry::Monads[:result]

      def initialize(event_store:)
        @event_store = event_store
      end

      def call(planned_facts:)
        @event_store.multiple { write(planned_facts) }
      end

      private

      def write(planned_facts)
        resolved = planned_facts.map { resolve(_1) }
        failure = resolved.find(&:failure?)
        return failure if failure

        pairs = resolved.map(&:value!)
        persisted = pairs.map do |planned_fact, existing|
          existing || @event_store.append(planned_fact.target_stream, [ planned_fact.event ]).sole
        end
        TargetWriteResultV1.new(events: persisted, outcome: outcome(pairs))
          .then { Success(_1) }
      end

      def resolve(planned_fact)
        existing = @event_store.read_marked(
          planned_fact.target_stream,
          MarkedEventReadCriteria.new(
            event_type: planned_fact.event.type,
            marker: planned_fact.target_event_marker,
            maximum_count: 1,
            direction: :asc
          )
        ).first
        return Success([ planned_fact, nil ]) unless existing
        return Success([ planned_fact, existing ]) if equivalent?(existing, planned_fact)

        Failure(
          TargetWriteErrorV1.new(
            code: :existing_target_mismatch,
            message: "A planned migration target marker resolves to different persisted facts",
            target_event_id: planned_fact.event.id,
            existing_event_id: existing.id
          )
        )
      end

      def equivalent?(existing, planned_fact)
        proposed = planned_fact.event
        existing.id == proposed.id &&
          existing.type == proposed.type &&
          existing.stream.context == planned_fact.target_stream.context &&
          existing.stream.stream_name == planned_fact.target_stream.stream_name &&
          existing.stream.stream_id == planned_fact.target_stream.stream_id &&
          existing.data == proposed.data &&
          existing.metadata.slice(*proposed.metadata.keys) == proposed.metadata &&
          existing.markers.sort == proposed.markers.sort &&
          existing.causation_id == proposed.caused_by&.id &&
          existing.correlation_id == proposed.correlation_id
      end

      def outcome(pairs)
        existing_count = pairs.count { _2 }
        return "written" if existing_count.zero?
        return "existing" if existing_count == pairs.length

        "mixed"
      end
    end
  end
end

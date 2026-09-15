# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyMarkedEventLocator
      include Dry::Monads[:result]

      def initialize(event_store:)
        @event_store = event_store
      end

      def call(
        source_event:,
        source_upper_position:,
        stream_context:,
        stream_name:,
        event_type:,
        marker:
      )
        event = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context:,
            stream_name:,
            event_types: [ event_type ],
            markers: [ marker ],
            maximum_count: 1,
            direction: :asc,
            to_position: source_upper_position
          )
        ).first
        return Success(event) if event

        Failure(unresolved(source_event, event_type:, marker:))
      rescue EventHistoryLimitExceeded
        Failure(unresolved(source_event, event_type:, marker:))
      end

      private

      def unresolved(source_event, event_type:, marker:)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Historical #{event_type} reference is not unique in the frozen source range for #{marker}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

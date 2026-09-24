# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCommandEventLocator
      include Dry::Monads[:result]

      MAXIMUM_TASK_SUBMISSIONS_PER_COMMAND = 1_000

      def initialize(event_store:)
        @event_store = event_store
      end

      def task_submissions(command_id:, through_position:, source_event:)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorControl",
            stream_name: "CoordinationTask",
            event_types: [ "CoordinationTaskSubmitted" ],
            markers: [ "command:#{command_id}" ],
            maximum_count: MAXIMUM_TASK_SUBMISSIONS_PER_COMMAND,
            from_position: 0,
            to_position: through_position || source_event.global_position,
            direction: :asc
          )
        )
        Success(events)
      rescue EventHistoryLimitExceeded => error
        Failure(
          TransformationErrorV1.new(
            code: :ambiguous_source_reference,
            message: error.message,
            event_type: source_event.type,
            schema_version: source_event.metadata["schema_version"],
            source_event_id: source_event.id
          )
        )
      end
    end
  end
end

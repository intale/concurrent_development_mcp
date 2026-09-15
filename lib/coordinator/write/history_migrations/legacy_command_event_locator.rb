# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCommandEventLocator
      include Dry::Monads[:result]

      def initialize(event_store:)
        @event_store = event_store
      end

      def completion(command_id:, through_position:, source_event:)
        locate(
          command_id:,
          through_position:,
          source_event:,
          stream_name: "Command",
          event_type: "CommandCompleted"
        )
      end

      def task_submission(command_id:, through_position:, source_event:)
        locate(
          command_id:,
          through_position:,
          source_event:,
          stream_name: "CoordinationTask",
          event_type: "CoordinationTaskSubmitted"
        )
      end

      private

      def locate(command_id:, through_position:, source_event:, stream_name:, event_type:)
        events = @event_store.read_global_marked(
          GlobalMarkedEventReadCriteria.new(
            stream_context: "CoordinatorControl",
            stream_name:,
            event_types: [ event_type ],
            markers: [ "command:#{command_id}" ],
            maximum_count: 1,
            direction: :asc,
            to_position: through_position
          )
        )
        Success(events.first)
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

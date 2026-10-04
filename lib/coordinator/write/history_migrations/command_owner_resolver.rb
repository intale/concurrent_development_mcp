# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CommandOwnerResolver
      include Dry::Monads[:result]

      def initialize(event_store:, submission_resolver:, stream_identity_allocator:)
        @event_store = event_store
        @submission_resolver = submission_resolver
        @stream_identity_allocator = stream_identity_allocator
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:)
        command_id = source_event.metadata["command_id"]
        return Success(nil) unless command_id

        submission = @submission_resolver.for_completion(
          source_event:, source_upper_position:, command_id:
        )
        return submission if submission.failure?

        identity_event = submission.value!&.command_identity_event || @event_store.read_at(
          StreamReference.new(context: "CoordinatorControl", stream_name: "Command", stream_id: command_id),
          0
        )
        return Success(nil) unless identity_event && identity_event.global_position <= source_upper_position

        @stream_identity_allocator.call(
          migration_id:, source_config_name:, source_event: identity_event,
          target_stream_context: "CoordinatorControl", target_stream_name: "Command", identity_role: "command"
        ).fmap { _1.target_stream.stream_id }
      end
    end
  end
end

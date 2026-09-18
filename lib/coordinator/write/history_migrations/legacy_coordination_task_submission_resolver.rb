# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCoordinationTaskSubmissionResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        command_event_locator:,
        schema_registry: LegacyEventSchemaRegistry.new,
        canonical_json: CanonicalJson.new
      )
        @event_store = event_store
        @command_event_locator = command_event_locator
        @schema_registry = schema_registry
        @canonical_json = canonical_json
      end

      def call(source_event:, source_upper_position:)
        submission_event = submission_event_for(source_event)
        submission = load_submission(submission_event)
        validate_submission!(submission_event, submission)

        canonical = @command_event_locator.task_submission(
          command_id: submission.command_id,
          through_position: source_upper_position,
          source_event:
        )
        return canonical if canonical.failure?

        canonical_event = canonical.value!
        raise ArgumentError, "legacy Command has no Task submission" unless canonical_event

        canonical_submission = load_submission(canonical_event)
        validate_submission!(canonical_event, canonical_submission)
        validate_replay!(submission, canonical_submission)

        Success(
          LegacyCoordinationTaskSubmissionResolutionV1.new(
            submission_event:,
            submission:,
            canonical_event:,
            canonical_submission:
          )
        )
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      private

      def submission_event_for(source_event)
        return source_event if source_event.type == "CoordinationTaskSubmitted"

        reference = StreamReference.new(
          context: source_event.stream.context,
          stream_name: source_event.stream.stream_name,
          stream_id: source_event.stream.stream_id
        )
        @event_store.read(
          reference,
          EventReadCriteria.new(
            event_types: [ "CoordinationTaskSubmitted" ],
            maximum_count: 1,
            direction: :asc,
            to_revision: source_event.stream_revision
          )
        ).first || raise(ArgumentError, "legacy Task lifecycle has no submission")
      end

      def load_submission(event)
        payload = @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        unless payload.is_a?(LegacyEvents::CoordinationTaskSubmittedV2)
          raise ArgumentError, "legacy Task submission contract is invalid"
        end

        payload
      end

      def validate_submission!(event, submission)
        valid = event.stream.context == "CoordinatorControl" &&
                event.stream.stream_name == "CoordinationTask" &&
                event.stream.stream_id == submission.task_id &&
                event.markers.include?("task:#{submission.task_id}") &&
                event.markers.include?("command:#{submission.command_id}")
        raise ArgumentError, "legacy Task submission identity is invalid" unless valid
      end

      def validate_replay!(submission, canonical)
        valid = submission.command_id == canonical.command_id &&
                submission.tool_name == canonical.tool_name &&
                submission.poll_interval_ms == canonical.poll_interval_ms &&
                submission.ttl_ms == canonical.ttl_ms &&
                canonical_input(submission) == canonical_input(canonical)
        return if valid

        raise ArgumentError, "legacy Command ID was reused with a different Task request"
      end

      def canonical_input(submission)
        input = submission.command_input
        @canonical_json.encode(input.is_a?(Hash) ? input : input.to_h)
      end

      def invalid(source_event, message)
        TransformationErrorV1.new(
          code: :ambiguous_source_reference,
          message: "Legacy CoordinationTask replay is invalid: #{message}",
          event_type: source_event.type,
          schema_version: source_event.metadata["schema_version"],
          source_event_id: source_event.id
        )
      end
    end
  end
end

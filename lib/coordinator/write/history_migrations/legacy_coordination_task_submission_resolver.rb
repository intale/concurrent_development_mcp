# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class LegacyCoordinationTaskSubmissionResolver
      include Dry::Monads[:result]

      def initialize(
        event_store:,
        command_event_locator:,
        schema_registry: SourceEventSchemaRegistry.new,
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
        if post_remodel?(submission)
          return current_resolution(
            submission_event:,
            submission:,
            source_upper_position:
          )
        end

        pairs = submission_pairs(
          command_id: submission.command_id,
          source_upper_position:,
          source_event:
        )
        return pairs if pairs.failure?

        Success(resolve_legacy(submission_event:, submission:, pairs: pairs.value!))
      rescue KeyError, ArgumentError, TypeError, Dry::Struct::Error, EventHistoryLimitExceeded => error
        Failure(invalid(source_event, error.message))
      end

      def for_completion(source_event:, source_upper_position:, command_id:)
        pairs = submission_pairs(command_id:, source_upper_position:, source_event:)
        return pairs if pairs.failure?
        return Success(nil) if pairs.value!.empty?

        correlated = pairs.value!.select do |event, _submission|
          source_event.correlation_id && event.correlation_id == source_event.correlation_id
        end
        candidates = if correlated.empty?
          grouped = pairs.value!.group_by { |_event, submission| request_key(submission) }
          raise ArgumentError, "legacy Command completion cannot be assigned to one Task request" unless grouped.one?

          grouped.values.sole
        else
          correlated
        end
        keys = candidates.map { |_event, submission| request_key(submission) }.uniq
        raise ArgumentError, "legacy Command completion matches different Task requests" unless keys.one?

        submission_event, submission = candidates.first
        if post_remodel?(submission)
          return current_resolution(
            submission_event:,
            submission:,
            source_upper_position:
          )
        end

        Success(resolve_legacy(submission_event:, submission:, pairs: pairs.value!))
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
        unless payload.is_a?(LegacyEvents::CoordinationTaskSubmittedV2) || post_remodel?(payload)
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

      def submission_pairs(command_id:, source_upper_position:, source_event:)
        events = @command_event_locator.task_submissions(
          command_id:,
          through_position: source_upper_position,
          source_event:
        )
        return events if events.failure?

        Success(
          events.value!.filter_map do |event|
            next unless [ 2, 3 ].include?(event.metadata["schema_version"])

            submission = load_submission(event)
            validate_submission!(event, submission)
            [ event, submission ]
          end
        )
      end

      def resolve_legacy(submission_event:, submission:, pairs:)
        canonical_event, canonical_submission = pairs.find do |_event, candidate|
          !post_remodel?(candidate) && request_key(candidate) == request_key(submission)
        end
        raise ArgumentError, "legacy Command has no matching Task submission" unless canonical_event

        LegacyCoordinationTaskSubmissionResolutionV1.new(
          submission_event:,
          submission:,
          canonical_event:,
          canonical_submission:,
          command_identity_event: canonical_event
        )
      end

      def current_resolution(submission_event:, submission:, source_upper_position:)
        command_event = current_command_event(
          submission,
          source_upper_position: source_upper_position || submission_event.global_position
        )
        Success(
          LegacyCoordinationTaskSubmissionResolutionV1.new(
            submission_event:,
            submission:,
            canonical_event: submission_event,
            canonical_submission: submission,
            command_identity_event: command_event
          )
        )
      end

      def current_command_event(submission, source_upper_position:)
        event = @event_store.read_at(
          StreamReference.new(
            context: "CoordinatorControl",
            stream_name: "Command",
            stream_id: submission.command_id
          ),
          0
        )
        payload = event && @schema_registry.load(
          type: event.type,
          schema_version: event.metadata.fetch("schema_version"),
          data: event.data
        )
        valid = event && event.global_position <= source_upper_position &&
                payload.is_a?(Events::CommandRegisteredV1) &&
                payload.command_id == submission.command_id
        raise ArgumentError, "current Task submission has no valid Command registration" unless valid

        event
      end

      def post_remodel?(submission)
        submission.is_a?(PostRemodelEvents::CoordinationTaskSubmittedV3)
      end

      def request_key(submission)
        [
          submission.command_id,
          submission.tool_name,
          submission.poll_interval_ms,
          submission.ttl_ms,
          canonical_input(submission)
        ]
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

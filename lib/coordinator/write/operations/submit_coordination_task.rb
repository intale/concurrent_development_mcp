# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class SubmitCoordinationTask
      include Dry::Monads[:result]

      MAX_ATTEMPTS = 3
      POLL_INTERVAL_MS = 500

      def initialize(
        event_store:,
        decider: Domain::CoordinationTasks::Submit.new,
        input_digest: CommandInputDigest.new,
        clock: SystemClock.new,
        id_generator: IdGenerator.new,
        event_factory: EventFactory.new,
        stream_factory: StreamFactory.new,
        execution_lane: Tasks::ExecutionLane.new,
        correlation_resolver: Tasks::CorrelationResolver.new(
          release_set_correlation_loader: ReleaseSets::CorrelationLoader.new(event_store:)
        ),
        maximum_attempts: MAX_ATTEMPTS
      )
        @event_store = event_store
        @decider = decider
        @input_digest = input_digest
        @clock = clock
        @id_generator = id_generator
        @event_factory = event_factory
        @stream_factory = stream_factory
        @execution_lane = execution_lane
        @correlation_resolver = correlation_resolver
        @maximum_attempts = maximum_attempts
      end

      def call(target_command)
        command_input = @input_digest.document(target_command)
        submitted_at = @clock.now
        correlation_id = @correlation_resolver.call(target_command)
        last_task_id = nil

        @maximum_attempts.times do
          task_id = @id_generator.uuid_v7
          last_task_id = task_id
          command = Commands::SubmitCoordinationTask.new(
            task_id:,
            tool_name: command_input.tool_name,
            command_id: target_command.command_id,
            command_input:,
            submitted_at:,
            ttl_ms: nil,
            poll_interval_ms: POLL_INTERVAL_MS
          )
          event = @decider.call(
            state: Domain::CoordinationTasks::State.initial,
            command:
          ).value!

          begin
            append(event:, target_command:, correlation_id:)
            return Success(Domain::CoordinationTasks::State.reduce([ event ]))
          rescue PgEventstore::WrongExpectedRevisionError
            next
          end
        end

        Failure(concurrency_conflict(last_task_id))
      end

      private

      def append(event:, target_command:, correlation_id:)
        persisted = @event_factory.build!(
          event:,
          event_id: @id_generator.uuid_v7,
          metadata: EventMetadata.new(
            command_id: target_command.command_id,
            actor_kind: target_command.actor.kind,
            actor_id: target_command.actor.id,
            recorded_by: "coordinator",
            policy_version: "coordination-task/v2"
          ),
          markers: [
            "task:#{event.task_id}",
            "command:#{target_command.command_id}",
            @execution_lane.marker(target_command.command_id),
            "tool:#{event.tool_name}"
          ],
          correlation_id:
        )

        @event_store.append(
          @stream_factory.coordination_task(event.task_id),
          [ persisted ],
          expected_revision: :no_stream
        )
      end

      def concurrency_conflict(task_id)
        Tasks::LifecycleError.new(
          code: :concurrency_conflict,
          message: "Could not allocate a Task ID; the request may succeed if retried",
          task_id:
        )
      end
    end
  end
end

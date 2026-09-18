# frozen_string_literal: true

module Coordinator::Write
  module HistoryMigrations
    class CoordinationTaskLifecycleTransformer
      include Dry::Monads[:result]

      def initialize(
        stream_identity_allocator:,
        rejection_retryability: LegacyCommandRejectionRetryability.new,
        task_failure_mapper: LegacyTaskFailureMapper.new
      )
        @stream_identity_allocator = stream_identity_allocator
        @rejection_retryability = rejection_retryability
        @task_failure_mapper = task_failure_mapper
      end

      def call(migration_id:, source_config_name:, source_upper_position:, source_event:, source_payload:)
        task = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "CoordinationTask",
          identity_role: "coordination-task"
        )
        return task if task.failure?

        facts = task_facts(source_payload, target_stream: task.value!.target_stream)
        return Success(facts) unless domain_rejection?(source_payload)

        command = allocate(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_name: "Command",
          identity_role: "command"
        )
        return command if command.failure?

        Success(
          [ rejection_fact(source_payload.result, target_stream: command.value!.target_stream) ] + facts
        )
      end

      private

      def allocate(migration_id:, source_config_name:, source_event:, target_stream_name:, identity_role:)
        @stream_identity_allocator.call(
          migration_id:,
          source_config_name:,
          source_event:,
          target_stream_context: "CoordinatorControl",
          target_stream_name:,
          identity_role:
        )
      end

      def task_facts(source, target_stream:)
        task_id = target_stream.stream_id
        [
          TransformedFactV1.new(
            target_stream:,
            event: target_event(source, task_id:),
            markers: [ "task:#{task_id}" ],
            step_name: step_name(source)
          )
        ]
      end

      def target_event(source, task_id:)
        case source
        when LegacyEvents::CoordinationTaskExecutionStartedV1
          Events::CoordinationTaskExecutionStartedV2.new(task_id:)
        when LegacyEvents::CoordinationTaskCancellationRequestedV1
          Events::CoordinationTaskCancellationRequestedV2.new(task_id:, reason: nil)
        when LegacyEvents::CoordinationTaskCancelledV1
          Events::CoordinationTaskCancelledV2.new(task_id:, reason: source.reason)
        when LegacyEvents::CoordinationTaskCompletedV2
          Events::CoordinationTaskCompletedV3.new(task_id:)
        when LegacyEvents::CoordinationTaskFailedV1
          Events::CoordinationTaskFailedV2.new(
            task_id:,
            code: @task_failure_mapper.code(source.error.code),
            reason: source.error.message,
            retryable: false
          )
        end
      end

      def step_name(source)
        case source
        when LegacyEvents::CoordinationTaskExecutionStartedV1 then "start-coordination-task"
        when LegacyEvents::CoordinationTaskCancellationRequestedV1 then "request-coordination-task-cancellation"
        when LegacyEvents::CoordinationTaskCancelledV1 then "cancel-coordination-task"
        when LegacyEvents::CoordinationTaskCompletedV2 then "complete-coordination-task"
        when LegacyEvents::CoordinationTaskFailedV1 then "fail-coordination-task"
        end
      end

      def domain_rejection?(source)
        source.is_a?(LegacyEvents::CoordinationTaskCompletedV2) &&
          (
            source.result.is_a?(LegacyTaskResults::DomainRejectionV1) ||
            source.result.is_a?(Tasks::SemanticResultV1::DomainRejection)
          )
      end

      def rejection_fact(result, target_stream:)
        command_id = target_stream.stream_id
        TransformedFactV1.new(
          target_stream:,
          event: Events::CommandRejectedV1.new(
            command_id:,
            code: result.error.code,
            reason: result.error.message,
            retryable: @rejection_retryability.call(result.error.code)
          ),
          markers: [ "command:#{command_id}" ],
          step_name: "reject-command"
        )
      end
    end
  end
end

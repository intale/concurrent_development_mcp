# frozen_string_literal: true

module Coordinator::Processes
  module ProcessManagers
    class CoordinationTaskExecutor
      include Dry::Monads[:result]

      INTERNAL_ERROR = Coordinator::Write::Tasks::OutcomeV3::Failed.new(
        code: "internal_error",
        reason: "Internal error",
        retryable: false
      )

      def initialize(
        event_store:,
        source_builder: CoordinationTaskSourceBuilder.new,
        task_loader: Coordinator::Write::Tasks::Loader.new(event_store:),
        transition: Coordinator::Write::Operations::ApplyCoordinationTaskTransition.new(
          event_store:,
          loader: task_loader
        ),
        start_task: Coordinator::Write::Operations::StartCoordinationTask.new(transition:),
        record_outcome: Coordinator::Write::Operations::RecordCoordinationTaskOutcome.new(transition:),
        target_command_builder: Coordinator::Write::Tasks::TargetCommandBuilder.new,
        target_executor: Coordinator::Write::Tasks::TargetExecutor.new(event_store:)
      )
        @source_builder = source_builder
        @task_loader = task_loader
        @start_task = start_task
        @record_outcome = record_outcome
        @target_command_builder = target_command_builder
        @target_executor = target_executor
      end

      def call(event)
        source = @source_builder.call(event)
        started_state = transition_value!(
          @start_task.call(task_id: source.payload.task_id, caused_by: source.event),
          transition: "start"
        )
        return nil if started_state.terminal?

        started_event = execution_started_event(source.payload.task_id)
        command = @target_command_builder.call(source.payload.command_input)
        ActiveSupport::Notifications.instrument(
          "coordinator.command_boundary",
          operation: "coordination_task_execute",
          command_id: command.command_id,
          task_id: source.payload.task_id,
          tool_name: source.payload.tool_name
        )
        outcome, parent_event = execute_target(command, started_event:)
        transition_value!(
          @record_outcome.call(
            task_id: source.payload.task_id,
            outcome:,
            caused_by: parent_event
          ),
          transition: "outcome"
        )

        nil
      end

      private

      def execution_started_event(task_id)
        event = @task_loader.call(task_id).persisted_events.find do |persisted|
          persisted.type == "CoordinationTaskExecutionStarted"
        end
        return event if event

        raise CoordinationTaskExecutionRejected,
              "Task #{task_id} is nonterminal without a persisted execution-started event"
      end

      def execute_target(command, started_event:)
        resolution = resolve_target(command, started_event:)
        if resolution.failure?
          return [ INTERNAL_ERROR, started_event ]
        end

        execution = resolution.value!
        [ Coordinator::Write::Tasks::OutcomeV3::Completed.new, execution.terminal_event ]
      end

      def resolve_target(command, started_event:)
        @target_executor.call(command, caused_by: started_event)
      rescue StandardError => error
        Rails.error.report(error, handled: true)
        Failure(INTERNAL_ERROR)
      end

      def transition_value!(result, transition:)
        return result.value! if result.success?

        failure = result.failure
        raise CoordinationTaskExecutionRejected,
              "Task #{transition} rejected: #{failure.code} - #{failure.message}"
      end
    end
  end
end
